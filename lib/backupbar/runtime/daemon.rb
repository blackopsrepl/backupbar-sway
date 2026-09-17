# frozen_string_literal: true

module BackupBar
  module Runtime
    module Daemon
      ERROR_BACKOFF_SECONDS = 15

      module_function

      def run(config_path, once: false)
        config = Core::Config.load_config(config_path)
        return refresh(config_path, config: config) if once

        lock = State.acquire_daemon_lock(config)
        raise "backupbar daemon already running for #{State.state_dir(config)}" unless lock

        loop do
          begin
            refresh(config_path, config: config)
            wait(config.dig(:source, :refreshSeconds).to_i)
          rescue StandardError => e
            warn "backupbar refresh error: #{Core::Format.clean_text(e.message)}"
            wait(ERROR_BACKOFF_SECONDS)
          end
          config = Core::Config.load_config(config_path)
        end
      ensure
        lock&.close
      end

      def refresh(config_path, config: nil)
        config ||= Core::Config.load_config(config_path)
        snapshot = nil
        changed = false
        State.with_refresh_lock(config) do
          previous = State.read_snapshot(config)
          raw = Core::Collectors.new(config).collect
          snapshot = Presenter.apply(raw, config)
          changed = State.materially_changed?(previous, snapshot)
          State.write_snapshot(config, snapshot)
        end
        signal_waybar(config) if changed
        snapshot
      rescue StandardError => e
        build_error_snapshot(config || Core::Config.load_config(config_path), e)
      end

      def build_error_snapshot(config, error)
        now = Time.now
        previous = State.read_snapshot(config)
        base = previous || {
          systems: [],
          storage: [],
          timeline: [],
          summary: {},
          view: {}
        }
        snapshot = base.merge(
          snapshotVersion: State::SNAPSHOT_VERSION,
          generatedAt: Core::Format.iso_time(now),
          status: "critical",
          source: { status: "error", sourceErrors: 1, error: Core::Format.clean_text(error.message) }
        )
        State.write_snapshot(config, snapshot)
        snapshot
      end

      def signal_waybar(config)
        signal = config.dig(:runtime, :waybarSignal).to_i
        return if signal <= 0

        Core::Process.run_command("pkill", ["-RTMIN+#{signal}", "waybar"], timeout: 2)
      rescue StandardError
        nil
      end

      def wait(seconds)
        sleep([seconds.to_i, 1].max)
      end
    end
  end
end
