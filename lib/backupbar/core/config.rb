# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module BackupBar
  module Core
    module Config
      CONFIG_VERSION = 1
      DEFAULT_QUICKSHELL_COMMAND = "quickshell"
      DEFAULT_STATE_DIR = File.join(Dir.home, ".local", "state", "backupbar")

      module_function

      def default_config_path
        File.join(Dir.home, ".config", "backupbar", "config.json")
      end

      def default_config
        {
          version: CONFIG_VERSION,
          source: {
            refreshSeconds: 60,
            commandTimeoutSeconds: 20,
            journalLines: 100,
            resticConfig: File.join(Dir.home, ".config", "solverforge", "backup.conf"),
            userAnacron: File.join(Dir.home, ".anacrontab"),
            borgConfig: ENV.fetch("BACKUPBAR_BORG_CONFIG", "/etc/borg/borg-config.yaml"),
            borgBinary: ENV.fetch("BACKUPBAR_BORG_BINARY", "borg-timemachine"),
            mountPaths: [
              { id: "root", label: "System", path: "/" }
            ]
          },
          runtime: {
            stateDir: DEFAULT_STATE_DIR,
            waybarSignal: 13,
            quickShellCommand: DEFAULT_QUICKSHELL_COMMAND,
            quickShellShell: File.join(
              Dir.home,
              ".local",
              "share",
              "backupbar",
              "frontend",
              "quickshell",
              "shell.qml"
            )
          },
          display: {
            staleAfterSeconds: 240,
            maxTimeline: 12
          }
        }
      end

      def load_config(path = default_config_path, validate: true)
        expanded = File.expand_path(path)
        raw = File.file?(expanded) ? JSON.parse(File.read(expanded), symbolize_names: true) : {}
        config = normalize_config(raw)
        validate_config!(config) if validate
        config
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid BackupBar config #{path}: #{e.message}"
      end

      def save_config(config, path = default_config_path)
        normalized = normalize_config(config)
        validate_config!(normalized)
        expanded = File.expand_path(path)
        FileUtils.mkdir_p(File.dirname(expanded))
        atomic_write_json(expanded, normalized)
      end

      def init_config(path = default_config_path)
        save_config(default_config, path)
      end

      def normalize_config(input)
        merged = deep_merge(default_config, symbolize(input || {}))
        merged[:version] = merged[:version].to_i
        merged[:source][:refreshSeconds] = merged[:source][:refreshSeconds].to_i
        merged[:source][:commandTimeoutSeconds] = merged[:source][:commandTimeoutSeconds].to_i
        merged[:source][:journalLines] = merged[:source][:journalLines].to_i
        merged[:runtime][:waybarSignal] = merged[:runtime][:waybarSignal].to_i
        merged[:source][:resticConfig] = normalize_path(merged[:source][:resticConfig])
        merged[:source][:userAnacron] = normalize_path(merged[:source][:userAnacron])
        merged[:source][:borgConfig] = normalize_path(merged[:source][:borgConfig])
        merged[:source][:borgBinary] = normalize_path(merged[:source][:borgBinary])
        merged[:runtime][:stateDir] = normalize_path(merged[:runtime][:stateDir])
        merged[:runtime][:quickShellShell] = normalize_path(merged[:runtime][:quickShellShell])
        merged[:display][:staleAfterSeconds] = merged[:display][:staleAfterSeconds].to_i
        merged[:display][:maxTimeline] = merged[:display][:maxTimeline].to_i
        merged[:source][:mountPaths] = normalize_mount_paths(merged[:source][:mountPaths])
        merged
      end

      def validate_config(config)
        issues = []
        issues << issue("error", "version", "must be #{CONFIG_VERSION}") unless config[:version] == CONFIG_VERSION
        minimum(issues, config.dig(:source, :refreshSeconds), 15, "source.refreshSeconds")
        minimum(issues, config.dig(:source, :commandTimeoutSeconds), 2, "source.commandTimeoutSeconds")
        bounded(issues, config.dig(:source, :journalLines), 10, 500, "source.journalLines")
        minimum(issues, config.dig(:display, :staleAfterSeconds), 60, "display.staleAfterSeconds")
        bounded(issues, config.dig(:display, :maxTimeline), 4, 30, "display.maxTimeline")
        bounded(issues, config.dig(:runtime, :waybarSignal), 1, 31, "runtime.waybarSignal")
        issues << issue("error", "runtime.stateDir", "must be set") if config.dig(:runtime, :stateDir).to_s.empty?
        issues
      end

      def validate_config!(config)
        errors = validate_config(config).select { |issue| issue[:severity] == "error" }
        raise ArgumentError, errors.map { |issue| "#{issue[:field]} #{issue[:message]}" }.join(", ") unless errors.empty?

        config
      end

      def normalize_mount_paths(paths)
        Array(paths).filter_map do |item|
          value = symbolize(item || {})
          path = normalize_path(value[:path])
          next if path.empty?

          {
            id: value[:id].to_s.empty? ? path : value[:id].to_s,
            label: value[:label].to_s.empty? ? path : value[:label].to_s,
            path: path
          }
        end.uniq { |item| item[:path] }
      end

      def normalize_path(value)
        text = value.to_s.strip
        text.empty? ? text : File.expand_path(text)
      end

      def minimum(issues, value, minimum_value, field)
        issues << issue("error", field, "must be at least #{minimum_value}") if value.to_i < minimum_value
      end

      def bounded(issues, value, minimum_value, maximum_value, field)
        issues << issue("error", field, "must be between #{minimum_value} and #{maximum_value}") unless (minimum_value..maximum_value).cover?(value.to_i)
      end

      def issue(severity, field, message)
        { severity: severity, field: field, message: message }
      end

      def symbolize(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, inner), out| out[key.to_sym] = symbolize(inner) }
        when Array
          value.map { |inner| symbolize(inner) }
        else
          value
        end
      end

      def deep_merge(base, override)
        base.merge(override) do |_key, old_value, new_value|
          old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
        end
      end

      def atomic_write_json(path, payload)
        temp_path = "#{path}.tmp.#{$$}.#{SecureRandom.hex(6)}"
        File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write("#{JSON.pretty_generate(payload)}\n")
        end
        File.rename(temp_path, path)
        File.chmod(0o600, path)
        payload
      ensure
        FileUtils.rm_f(temp_path) if temp_path && File.exist?(temp_path)
      end
    end
  end
end
