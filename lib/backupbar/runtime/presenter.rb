# frozen_string_literal: true

module BackupBar
  module Runtime
    module Presenter
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
        storage = Array(raw[:storage])
        summary = build_summary(systems, storage, now)
        status = overall_status(systems, storage)
        timeline = Array(raw[:timeline]).map { |event| present_event(event, now) }
        source = raw[:source] || {}
        chip = chip_view(summary, status)

        {
          snapshotVersion: Runtime::State::SNAPSHOT_VERSION,
          generatedAt: Core::Format.iso_time(now),
          status: status,
          source: source,
          systems: systems.sort_by { |system| [STATUS_ORDER.fetch(system[:status], 9), system[:label].to_s] },
          storage: storage,
          timeline: timeline,
          summary: summary,
          view: {
            chip: chip,
            summary: summary,
            systems: systems.sort_by { |system| [STATUS_ORDER.fetch(system[:status], 9), system[:label].to_s] },
            storage: storage,
            timeline: timeline,
            staleAfterSeconds: config.dig(:display, :staleAfterSeconds).to_i,
            source: source
          }
        }
      end

      def present_system(system, now)
        system.merge(
          ageSeconds: Core::Format.age_seconds(system[:latestAt], now),
          latestText: system[:latestAt] ? Core::Format.relative_time(system[:latestAt], now) : system[:latestText].to_s,
          statusLabel: system[:status].to_s.tr("-", " ").upcase,
          statusRank: STATUS_ORDER.fetch(system[:status].to_s, 9)
        )
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
        {
          systemCount: systems.length,
          backupCount: backups.length,
          healthyCount: systems.count { |system| system[:status] == "healthy" },
          activeCount: systems.count { |system| system[:status] == "active" },
          attentionCount: attention,
          criticalCount: systems.count { |system| system[:status] == "critical" },
          latestGoodAt: Core::Format.iso_time(latest),
          latestGoodText: latest ? Core::Format.relative_time(latest, now) : "no successful backup observed",
          storageWarningCount: storage.count { |mount| %w[critical warning].include?(mount[:status]) },
          hottestMount: max_mount && max_mount[:label],
          hottestPercent: max_mount && max_mount[:usePercent],
          generatedText: "refreshed #{Core::Format.relative_time(now, now)}"
        }
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
