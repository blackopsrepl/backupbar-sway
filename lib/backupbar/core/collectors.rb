# frozen_string_literal: true

require "json"
require "time"

module BackupBar
  module Core
    class Collectors
      RESTIC_SECRET_TAG = "solverforge-secrets"
      ICON_BORG = "\u{f048b}" # md-server
      ICON_RESTIC = "\u{f01bc}" # md-database
      ICON_SECRETS = "\u{f033e}" # md-lock
      ICON_METADATA = "\u{f0219}" # md-file-document
      ICON_SNAPPER = "\u{f02da}" # md-history
      ICON_MAINTENANCE = "\u{f02ca}" # md-harddisk
      ICON_UNKNOWN = "\u{f0625}" # md-help-circle-outline

      def initialize(config, runner: Process)
        @config = config
        @runner = runner
        @timeout = config.dig(:source, :commandTimeoutSeconds).to_i
      end

      def collect(now: Time.now)
        systems = [
          collect_borg(now),
          collect_restic(now),
          collect_secret_archive(now),
          collect_native_metadata(now),
          collect_snapper(now),
          collect_maintenance(now)
        ]
        storage = collect_storage(now)
        timeline = build_timeline(systems, storage, now)
        source_errors = systems.count { |system| system[:sourceStatus] == "error" }

        {
          systems: systems,
          storage: storage,
          timeline: timeline,
          source: {
            status: source_errors.positive? ? "partial" : "ok",
            sourceErrors: source_errors,
            queriedAt: Format.iso_time(now)
          }
        }
      end

      private

      def collect_borg(now)
        service = systemd_show("borg-timemachine.service")
        timer = systemd_show("borg-timemachine.timer")
        config = parse_borg_config(@config.dig(:source, :borgConfig))
        last_at = parse_systemd_time(service["ExecMainExitTimestamp"])
        running = service["ActiveState"] == "active"
        last_success = service["Result"] == "success" && service["ExecMainStatus"].to_i.zero?
        timer_active = timer["ActiveState"] == "active"
        status = if running
                   "active"
                 elsif !timer_active
                   "critical"
                 elsif !last_success && last_at
                   "critical"
                 elsif last_at.nil?
                   "unknown"
                 elsif Format.age_seconds(last_at, now).to_i > 7_200
                   "warning"
                 else
                   "healthy"
                 end

        info = read_borg_info(config[:binary], config[:path])
        source_status = service.empty? && timer.empty? ? "error" : "ok"
        {
          id: "borg",
          label: "Borg",
          kind: "backup",
          icon: ICON_BORG,
          status: status,
          sourceStatus: source_status,
          schedule: "hourly / persistent",
          cadence: "hourly",
          target: config[:path] || "configured Borg repository",
          retention: config[:retention] || "configured in /etc/borg/borg-config.yaml",
          latestAt: Format.iso_time(last_at),
          latestText: last_at ? Format.relative_time(last_at, now) : "no completed run observed",
          nextAt: parse_systemd_time(timer["NextElapseUSecRealtime"])&.iso8601,
          detail: running ? "Backup cycle in progress" : (last_success ? "Backup, prune, and compact completed" : "Last Borg cycle failed"),
          metrics: info,
          coverage: "#{config[:jobs] || "configured jobs"}"
        }
      rescue StandardError => e
        unavailable_system("borg", "Borg", "Borg probe failed: #{Format.clean_text(e.message)}", now)
      end

      def collect_restic(now)
        settings = restic_settings
        return unavailable_system("restic", "Restic", settings[:error], now) if settings[:error]

        result = run(
          "restic",
          ["--repo", settings[:repo], "--password-file", settings[:password], "snapshots", "--json"],
          timeout: [@timeout, 30].max
        )
        snapshots = result.success? ? JSON.parse(result.stdout) : []
        normal = snapshots.reject { |snapshot| Array(snapshot["tags"]).include?(RESTIC_SECRET_TAG) }
        latest = latest_snapshot(normal)
        latest_by_path = normal.flat_map { |snapshot| Array(snapshot["paths"]).map { |path| [path, snapshot] } }.to_h
        status = if !result.success? && latest.nil?
                   "critical"
                 elsif latest.nil?
                   "unknown"
                 elsif Format.age_seconds(latest["time"], now).to_i > 172_800
                   "warning"
                 else
                   "healthy"
                 end
        anacron = parse_user_anacron
        {
          id: "restic",
          label: "Restic",
          kind: "backup",
          icon: ICON_RESTIC,
          status: status,
          sourceStatus: result.success? ? "ok" : "error",
          schedule: anacron[:backup] || "daily via user anacron",
          cadence: "daily",
          target: redact_target(settings[:repo]),
          retention: anacron[:prune] || "prune via user anacron",
          latestAt: latest && latest["time"],
          latestText: latest ? Format.relative_time(latest["time"], now) : "no ordinary snapshot observed",
          detail: result.success? ? "#{normal.length} ordinary snapshots / #{snapshots.length - normal.length} secret snapshots" : Format.clean_text(result.stderr),
          metrics: {
            snapshotCount: snapshots.length,
            ordinarySnapshotCount: normal.length,
            secretSnapshotCount: snapshots.length - normal.length,
            pathCount: settings[:paths].length,
            latestPaths: latest_by_path.keys.sort
          },
          coverage: settings[:paths],
          events: normal.sort_by { |snapshot| snapshot["time"].to_s }.last(6).map do |snapshot|
            {
              time: snapshot["time"],
              label: "Restic",
              status: "healthy",
              detail: Array(snapshot["paths"]).join(", ")
            }
          end
        }
      rescue JSON::ParserError => e
        unavailable_system("restic", "Restic", "Snapshot JSON invalid: #{e.message}", now)
      rescue StandardError => e
        unavailable_system("restic", "Restic", "Restic probe failed: #{Format.clean_text(e.message)}", now)
      end

      def collect_secret_archive(now)
        timer = systemd_show("solverforge-backup-secrets.timer")
        settings = restic_settings
        secret_snapshots = []
        unless settings[:error]
          result = run("restic", ["--repo", settings[:repo], "--password-file", settings[:password], "snapshots", "--tag", RESTIC_SECRET_TAG, "--json"], timeout: [@timeout, 30].max)
          secret_snapshots = result.success? ? JSON.parse(result.stdout) : []
        end
        latest = latest_snapshot(secret_snapshots)
        timer_active = timer["ActiveState"] == "active"
        status = if latest.nil? && !timer_active
                   "critical"
                 elsif latest.nil?
                   "warning"
                 elsif Format.age_seconds(latest["time"], now).to_i > 172_800
                   "warning"
                 else
                   "healthy"
                 end
        {
          id: "secrets",
          label: "Secrets",
          kind: "backup",
          icon: ICON_SECRETS,
          status: status,
          sourceStatus: settings[:error] ? "error" : "ok",
          schedule: "daily / systemd timer",
          cadence: "daily",
          target: redact_target(settings[:repo]),
          retention: "Restic tag #{RESTIC_SECRET_TAG}",
          latestAt: latest && latest["time"],
          latestText: latest ? Format.relative_time(latest["time"], now) : "no secret archive observed",
          nextAt: parse_systemd_time(timer["NextElapseUSecRealtime"])&.iso8601,
          detail: latest ? "#{secret_snapshots.length} tagged snapshots" : "Waiting for the first tagged snapshot",
          metrics: { snapshotCount: secret_snapshots.length, timer: timer["ActiveState"] || "unknown" },
          coverage: "service keys and Forgejo SSH material"
        }
      rescue JSON::ParserError => e
        unavailable_system("secrets", "Secrets", "Secret snapshot JSON invalid: #{e.message}", now)
      rescue StandardError => e
        unavailable_system("secrets", "Secrets", "Secret archive probe failed: #{Format.clean_text(e.message)}", now)
      end

      def collect_native_metadata(now)
        rpmdb = systemd_show("backup-rpmdb.timer")
        sysconfig = systemd_show("backup-sysconfig.timer")
        records = [
          timer_record("RPM DB", rpmdb, now),
          timer_record("Sysconfig", sysconfig, now)
        ]
        active = records.all? { |record| record[:status] == "healthy" }
        {
          id: "metadata",
          label: "Native metadata",
          kind: "metadata",
          icon: ICON_METADATA,
          status: active ? "healthy" : "warning",
          sourceStatus: "ok",
          schedule: "daily / systemd timers",
          cadence: "daily",
          target: "/var/adm/backup",
          retention: "distribution-managed rotating copies",
          latestAt: records.map { |record| record[:latestAt] }.compact.max,
          latestText: records.map { |record| record[:latestText] }.join(" / "),
          detail: records.map { |record| "#{record[:label]} #{record[:detail]}" }.join("  ·  "),
          metrics: { jobs: records },
          coverage: "RPM database and /etc/sysconfig snapshots",
          events: records.filter_map do |record|
            next unless record[:latestAt]

            { time: record[:latestAt], label: record[:label], status: record[:status], detail: record[:detail] }
          end
        }
      rescue StandardError => e
        unavailable_system("metadata", "Native metadata", "Metadata probe failed: #{Format.clean_text(e.message)}", now)
      end

      def collect_snapper(now)
        timeline = systemd_show("snapper-timeline.timer")
        cleanup = systemd_show("snapper-cleanup.timer")
        config = read_snapper_config
        snapshot_count, latest_id = snapshot_directory_summary
        status = if timeline["ActiveState"] != "active" && cleanup["ActiveState"] != "active"
                   "warning"
                 elsif snapshot_count.zero?
                   "warning"
                 else
                   "healthy"
                 end
        {
          id: "snapper",
          label: "Snapper",
          kind: "rollback",
          icon: ICON_SNAPPER,
          status: status,
          sourceStatus: "ok",
          schedule: "timeline timer / cleanup timer",
          cadence: "hourly cleanup",
          target: "root Btrfs subvolume /",
          retention: "#{config[:numberMin] || "?"}-#{config[:numberMax] || "?"} snapshots",
          latestAt: parse_systemd_time(timeline["LastTriggerUSec"])&.iso8601,
          latestText: snapshot_count.positive? ? "#{snapshot_count} snapshots / latest #{latest_id}" : "no visible snapshots",
          nextAt: parse_systemd_time(timeline["NextElapseUSecRealtime"])&.iso8601,
          detail: config[:timelineCreate] == "no" ? "Rollback protection; timeline creation disabled" : "Local rollback snapshots",
          metrics: { snapshotCount: snapshot_count, timelineCreate: config[:timelineCreate], cleanup: cleanup["ActiveState"] || "unknown" },
          coverage: "root subvolume only"
        }
      rescue StandardError => e
        unavailable_system("snapper", "Snapper", "Snapper probe failed: #{Format.clean_text(e.message)}", now)
      end

      def collect_maintenance(now)
        timers = %w[btrfs-scrub.timer btrfs-balance.timer btrfs-trim.timer].to_h do |unit|
          [unit, systemd_show(unit)]
        end
        scrub = timers["btrfs-scrub.timer"]
        status = if scrub["ActiveState"] != "active"
                   "warning"
                 elsif (last = parse_systemd_time(scrub["LastTriggerUSec"])) && Format.age_seconds(last, now).to_i > 45 * 86_400
                   "warning"
                 else
                   "healthy"
                 end
        {
          id: "maintenance",
          label: "Btrfs care",
          kind: "integrity",
          icon: ICON_MAINTENANCE,
          status: status,
          sourceStatus: "ok",
          schedule: "scrub monthly / balance weekly",
          cadence: "maintenance",
          target: "Btrfs filesystems",
          retention: "not a backup",
          latestAt: parse_systemd_time(scrub["LastTriggerUSec"])&.iso8601,
          latestText: scrub["LastTriggerUSec"].to_s.empty? ? "no scrub observed" : Format.relative_time(scrub["LastTriggerUSec"], now),
          nextAt: parse_systemd_time(scrub["NextElapseUSecRealtime"])&.iso8601,
          detail: timers.map { |unit, values| "#{unit.delete_suffix(".timer")} #{values["ActiveState"] || "unknown"}" }.join("  ·  "),
          metrics: timers.transform_values { |values| values.slice("ActiveState", "LastTriggerUSec", "NextElapseUSecRealtime") },
          coverage: "integrity maintenance, not disaster recovery"
        }
      end

      def collect_storage(now)
        Array(@config.dig(:source, :mountPaths)).filter_map do |mount|
          result = run("df", ["-P", "-B1", mount[:path]], timeout: 5)
          next storage_unavailable(mount, result.stderr) unless result.success?

          row = result.stdout.lines.last.to_s.split
          next storage_unavailable(mount, "df returned no data") unless row.length >= 5

          total = row[-5].to_i
          used = row[-4].to_i
          available = row[-3].to_i
          use_percent = row[-2].to_s.delete("%").to_f
          {
            id: mount[:id],
            label: mount[:label],
            path: mount[:path],
            totalBytes: total,
            usedBytes: used,
            availableBytes: available,
            usePercent: use_percent,
            status: use_percent >= 95 ? "critical" : (use_percent >= 85 ? "warning" : "healthy"),
            detail: "#{Format.bytes(available)} free · #{use_percent.round}% used",
            queriedAt: Format.iso_time(now)
          }
        end
      end

      def build_timeline(systems, storage, now)
        events = systems.flat_map { |system| Array(system[:events]) + system_event(system) }
        events += storage.select { |mount| %w[warning critical].include?(mount[:status]) }.map do |mount|
          { time: Format.iso_time(now), label: mount[:label], status: mount[:status], detail: mount[:detail] }
        end
        events.sort_by { |event| Format.parse_time(event[:time]) || Time.at(0) }.reverse.first(@config.dig(:display, :maxTimeline).to_i)
      end

      def system_event(system)
        return [] unless system[:latestAt]

        [{ time: system[:latestAt], label: system[:label], status: system[:status], detail: system[:detail] }]
      end

      def timer_record(label, timer, now)
        last = parse_systemd_time(timer["LastTriggerUSec"])
        status = if timer["ActiveState"] != "active"
                   "warning"
                 elsif last.nil? || Format.age_seconds(last, now).to_i > 172_800
                   "warning"
                 else
                   "healthy"
                 end
        {
          label: label,
          status: status,
          latestAt: Format.iso_time(last),
          latestText: last ? Format.relative_time(last, now) : "unknown",
          detail: timer["ActiveState"] || "timer unavailable"
        }
      end

      def unavailable_system(id, label, detail, now)
        {
          id: id,
          label: label,
          kind: "backup",
          icon: ICON_UNKNOWN,
          status: "unknown",
          sourceStatus: "error",
          schedule: "unavailable",
          cadence: "unknown",
          target: "unavailable",
          retention: "unavailable",
          latestAt: nil,
          latestText: "not observed",
          detail: detail,
          metrics: {},
          coverage: "unavailable",
          events: [{ time: Format.iso_time(now), label: label, status: "unknown", detail: detail }]
        }
      end

      def storage_unavailable(mount, error)
        {
          id: mount[:id],
          label: mount[:label],
          path: mount[:path],
          totalBytes: 0,
          usedBytes: 0,
          availableBytes: 0,
          usePercent: nil,
          status: "unknown",
          detail: "unavailable: #{Format.clean_text(error)}"
        }
      end

      def systemd_show(unit)
        properties = %w[ActiveState SubState Result ExecMainStatus ExecMainExitTimestamp LastTriggerUSec NextElapseUSecRealtime]
        result = run("systemctl", ["show", unit, "--no-pager", "--property=#{properties.join(",")}"], timeout: 5)
        return {} unless result.success?

        result.stdout.lines.each_with_object({}) do |line, values|
          key, value = line.chomp.split("=", 2)
          values[key] = value.to_s if key
        end
      end

      def run(command, args, timeout: @timeout)
        @runner.run_command(command, args, timeout: timeout)
      end

      def parse_systemd_time(value)
        return nil if value.to_s.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def latest_snapshot(snapshots)
        Array(snapshots).max_by { |snapshot| Format.parse_time(snapshot["time"]) || Time.at(0) }
      end

      def restic_settings
        files = [
          File.join(Dir.home, ".local", "share", "solverforge", "default", "bash", "backup.conf"),
          @config.dig(:source, :resticConfig)
        ]
        parsed = files.select { |path| File.file?(path) }.reduce({}) { |values, path| values.merge(parse_shell_config(path)) }
        repo = parsed["RESTIC_REPO"].to_s
        password = expand_home(parsed["RESTIC_PASSWORD_FILE"])
        paths = Array(parsed["BACKUP_PATHS"]).map { |path| expand_home(path) }.reject(&:empty?)
        return { error: "Restic configuration not found" } if repo.empty? || password.empty?

        { repo: repo, password: password, paths: paths }
      rescue StandardError => e
        { error: "Restic configuration unreadable: #{Format.clean_text(e.message)}" }
      end

      def parse_shell_config(path)
        assignments = {}
        array_key = nil
        File.read(path).each_line do |line|
          if array_key
            if line.include?( ")")
              array_key = nil
            else
              value = line.match(/"([^"]+)"/)&.captures&.first
              (assignments[array_key] ||= []) << value if value
            end
            next
          end

          if (array = line.match(/\A\s*(BACKUP_PATHS)\s*=\s*\(/))
            array_key = array[1]
            assignments[array_key] = []
            next
          end

          match = line.match(/\A\s*([A-Z_]+)\s*=\s*["']([^"']*)["']/)
          assignments[match[1]] = match[2] if match
        end
        assignments
      end

      def expand_home(value)
        value.to_s.gsub("$HOME", Dir.home).sub(%r{\A~/}, "#{Dir.home}/")
      end

      def parse_user_anacron
        return {} unless File.file?(@config.dig(:source, :userAnacron))

        values = {}
        File.read(@config.dig(:source, :userAnacron)).each_line do |line|
          fields = line.strip.split(/\s+/, 4)
          next if fields.length < 4 || line.lstrip.start_with?("#")

          period, delay, identifier = fields.first(3)
          command = fields[3]
          if identifier == "cron.backup"
            values[:backup] = "#{period == '1' ? 'daily' : period} via user anacron (+#{delay}m)"
          elsif identifier == "cron.backup.prune"
            values[:prune] = "#{period == '7' ? 'weekly' : period} via user anacron (+#{delay}m)"
          end
          values[:command] = command if identifier == "cron.backup"
        end
        values
      rescue StandardError
        {}
      end

      def parse_borg_config(path)
        result = { binary: @config.dig(:source, :borgBinary), jobs: 0 }
        return result unless File.file?(path)

        in_repository = false
        in_retention = false
        File.read(path).each_line do |line|
          in_repository = true if line.strip == "repository:"
          in_retention = true if line.strip == "retention:"
          in_repository = false if line.match?(/^\S/) && line.strip != "repository:"
          in_retention = false if line.match?(/^\S/) && line.strip != "retention:"
          if in_repository && (match = line.match(/^\s+path:\s+(.+)$/))
            result[:path] = match[1].strip
          end
          if in_retention && (match = line.match(/^\s+(within|hourly|daily|weekly|monthly|yearly):\s+(.+)$/))
            result[:retention] ||= {}
            result[:retention][match[1]] = match[2].strip
          end
          result[:jobs] += 1 if line.match?(/^\s+- name:/)
        end
        result[:retention] = result[:retention]&.map { |key, value| "#{key} #{value}" }&.join(" · ")
        result[:retention] ||= "configured"
        result
      rescue StandardError
        result
      end

      def read_borg_info(binary, repository)
        return {} if binary.to_s.empty? || repository.to_s.empty?

        result = run("sudo", ["-n", binary, "--config", @config.dig(:source, :borgConfig), "info"], timeout: [@timeout, 30].max)
        return { status: "unavailable", error: Format.clean_text(result.stderr) } unless result.success?

        line = result.stdout.lines.find { |entry| entry.include?("All archives:") }
        { status: "ok", allArchives: line&.strip }
      end

      def snapshot_directory_summary
        result = run("sudo", ["-n", "find", "/.snapshots", "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-printf", "%f\\n"], timeout: 5)
        ids = result.success? ? result.stdout.lines.map(&:strip).grep(/\A\d+\z/) : []
        [ids.length, ids.max_by(&:to_i)]
      end

      def read_snapper_config
        path = "/etc/snapper/configs/root"
        return {} unless File.file?(path)

        values = {}
        File.read(path).each_line do |line|
          key, value = line.strip.split("=", 2)
          values[key] = value.to_s.delete('"') if key && value
        end
        {
          timelineCreate: values["TIMELINE_CREATE"],
          numberMin: values["NUMBER_MIN"],
          numberMax: values["NUMBER_MAX"]
        }
      rescue StandardError
        {}
      end

      def redact_target(repo)
        repo.to_s.sub(/:\/\/.+@/, "://")
      end
    end
  end
end
