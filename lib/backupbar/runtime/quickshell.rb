# frozen_string_literal: true

require "time"

module BackupBar
  module Runtime
    module QuickShell
      module_function

      def open(config_path)
        config = Core::Config.load_config(config_path)
        State.write_ui_state(config, { open: true, requestedAt: Time.now.utc.iso8601(6) })
        launch(config_path, config)
      end

      def close(config_path)
        config = Core::Config.load_config(config_path)
        State.write_ui_state(config, { open: false, requestedAt: Time.now.utc.iso8601(6) })
      end

      def toggle(config_path)
        config = Core::Config.load_config(config_path)
        State.read_ui_state(config)[:open] ? close(config_path) : open(config_path)
        State.read_ui_state(config)
      end

      def status(config_path)
        config = Core::Config.load_config(config_path)
        State.read_ui_state(config)
      end

      def launch(config_path, config = nil)
        config ||= Core::Config.load_config(config_path)
        shell = File.expand_path(config.dig(:runtime, :quickShellShell))
        command = config.dig(:runtime, :quickShellCommand).to_s
        env = {
          "BACKUPBAR_BIN" => resolved_binary,
          "BACKUPBAR_CONFIG" => File.expand_path(config_path),
          "BACKUPBAR_STATE_DIR" => State.state_dir(config),
          "QT_QPA_PLATFORM" => "wayland"
        }
        Core::Process.spawn_detached(command, ["--daemonize", "--no-duplicate", "--path", shell], env: env, cwd: File.dirname(shell))
      end

      def resolved_binary
        configured = ENV["BACKUPBAR_BIN"].to_s
        return configured unless configured.empty?

        candidate = File.join(Dir.home, ".local", "bin", "backupbar")
        File.executable?(candidate) ? candidate : "backupbar"
      end
    end
  end
end
