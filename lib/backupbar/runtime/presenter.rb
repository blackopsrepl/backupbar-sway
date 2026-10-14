# frozen_string_literal: true

module BackupBar
  module Runtime
    module Presenter
      # A backup that has not completed within 48 hours has missed at least one
      # daily cycle even if its timer still reports an active schedule; that is
      # the same threshold the collectors use to downgrade a backup to warning.
      BACKUP_OVERDUE_SECONDS = 172_800

      STATUS_ORDER = {
        "critical" => 0,
        "warning" => 1,
        "unknown" => 2,
        "active" => 3,
        "healthy" => 4
      }.freeze

      module_function

      def apply(raw, config, now: Time.now)
        systems = Array(raw[:systems]).map { |system| present_system(system, now) }
        ordered = systems.sort_by { |system| [STATUS_ORDER.fetch(system[:status], 9), system[:label].to_s] }
        storage = Array(raw[:storage])
        summary = build_summary(systems, storage, now)
        status = overall_status(systems, storage)
        timeline = Array(raw[:timeline]).map { |event| present_event(event, now) }
        source = raw[:source] || {}
        chip = chip_view(summary, status)
        view = {
          chip: chip,
          summary: summary,
          systems: ordered,
          storage: storage,
          timeline: timeline,
          staleAfterSeconds: config.dig(:display, :staleAfterSeconds).to_i,
          source: source,
          context: context_view(ordered, now)
        }

        {
          snapshotVersion: Runtime::State::SNAPSHOT_VERSION,
          generatedAt: Core::Format.iso_time(now),
          status: status,
          source: source,
          systems: ordered,
          storage: storage,
          timeline: timeline,
          summary: summary,
          view: view
        }
      end

      def present_system(system, now)
        next_at = Core::Format.parse_time(system[:nextAt])
        latest_age = Core::Format.age_seconds(system[:latestAt], now)
        latest_age = nil if latest_age&.negative?
        system.merge(
          ageSeconds: latest_age,
          latestText: system[:latestAt] ? Core::Format.relative_time(system[:latestAt], now) : system[:latestText].to_s,
          statusLabel: system[:status].to_s.tr("-", " ").upcase,
          statusRank: STATUS_ORDER.fetch(system[:status].to_s, 9),
          nextAtText: next_at ? "in #{Core::Format.duration([(next_at - now).ceil, 0].max)}" : nil,
          overdue: overdue?(system, latest_age, next_at, now),
          repoUsageText: repo_usage_text(system)
        )
      end

      # "Overdue" is a surfacing judgment only: the next scheduled run is already
      # in the past, or a backup has not completed within its expected window.
      # No scheduler or corrective action is implied anywhere downstream.
      def overdue?(system, latest_age, next_at, now)
        return next_at < now if next_at

        return false unless system[:kind] == "backup"
        return false unless latest_age

        latest_age > BACKUP_OVERDUE_SECONDS
      end

      # Repository footprint as the source already reports it (Borg's
      # deduplicated total). Presentation-only: nothing here queries a tool.
      def repo_usage_text(system)
        metrics = system[:metrics].is_a?(Hash) ? system[:metrics] : {}
        text = metrics[:repoUsageText].to_s.strip
        text.empty? ? nil : text
      end

      def present_event(event, now)
        event.merge(
          timeText: Core::Format.relative_time(event[:time], now),
          statusLabel: event[:status].to_s.tr("-", " ")
        )
      end

      def build_summary(systems, storage, now)
        backups = systems.select { |system| system[:kind] == "backup" }
        attention = systems.count { |system| %w[critical warning unknown].include?(system[:status]) }
        latest = backups.filter_map { |system| Core::Format.parse_time(system[:latestAt]) }.max
        max_mount = storage.compact.max_by { |mount| mount[:usePercent].to_f }
        summary = {
          systemCount: systems.length,
          backupCount: backups.length,
          healthyCount: systems.count { |system| system[:status] == "healthy" },
          activeCount: systems.count { |system| system[:status] == "active" },
          attentionCount: attention,
          criticalCount: systems.count { |system| system[:status] == "critical" },
          overdueCount: systems.count { |system| system[:overdue] },
          latestGoodAt: Core::Format.iso_time(latest),
          latestGoodText: latest ? Core::Format.relative_time(latest, now) : "no successful backup observed",
          storageWarningCount: storage.count { |mount| %w[critical warning].include?(mount[:status]) },
          hottestMount: max_mount && max_mount[:label],
          hottestPercent: max_mount && max_mount[:usePercent],
          generatedText: "refreshed #{Core::Format.relative_time(now, now)}"
        }
        summary[:headlineText] = headline_text(summary)
        summary
      end

      # One like-for-like headline: the same number-of-jobs basis the chip uses,
      # with an explicit overdue count next to it in the same plural style.
      def headline_text(summary)
        jobs = summary[:backupCount].to_i
        overdue = summary[:overdueCount].to_i
        "#{jobs} #{jobs == 1 ? "job" : "jobs"} / #{overdue} overdue"
      end

      def context_view(systems, now)
        upcoming = systems.filter_map do |system|
          next_at = Core::Format.parse_time(system[:nextAt])
          next_at && next_at >= now ? [next_at, system[:label].to_s] : nil
        end.min_by { |entry| entry[0] }

        if upcoming
          {
            nextRunAt: Core::Format.iso_time(upcoming[0]),
            nextRunLabel: upcoming[1],
            nextRunText: "in #{Core::Format.duration([(upcoming[0] - now).ceil, 0].max)}"
          }
        else
          {
            nextRunAt: nil,
            nextRunLabel: nil,
            nextRunText: nil
          }
        end
      end

      def overall_status(systems, storage)
        return "critical" if systems.any? { |system| system[:status] == "critical" } || storage.any? { |mount| mount[:status] == "critical" }
        return "warning" if systems.any? { |system| %w[warning unknown].include?(system[:status]) } || storage.any? { |mount| mount[:status] == "warning" }
        return "active" if systems.any? { |system| system[:status] == "active" }

        "healthy"
      end

      def chip_view(summary, status)
        healthy = summary[:healthyCount].to_i
        total = summary[:systemCount].to_i
        text = "BB #{healthy}/#{total}"
        text = "BB LIVE" if summary[:activeCount].to_i.positive?
        text = "BB !#{summary[:criticalCount]}" if status == "critical"
        classes = ["backupbar", status]
        classes << "attention" if summary[:attentionCount].to_i.positive?
        classes << "storage-hot" if summary[:storageWarningCount].to_i.positive?
        {
          text: text,
          classes: classes.uniq,
          tooltipLines: tooltip_lines(summary, status)
        }
      end

      def tooltip_lines(summary, status)
        [
          "BackupBar · #{status}",
          "#{summary[:healthyCount]}/#{summary[:systemCount]} systems healthy · #{summary[:attentionCount]} attention",
          "Latest successful observation: #{summary[:latestGoodText]}",
          summary[:hottestMount] ? "Storage peak: #{summary[:hottestMount]} #{summary[:hottestPercent].to_f.round}%" : nil,
          "Left click: open · middle click: re-read sources"
        ].compact
      end
    end
  end
end
