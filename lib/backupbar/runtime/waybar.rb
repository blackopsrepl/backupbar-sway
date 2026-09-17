# frozen_string_literal: true

require "json"

module BackupBar
  module Runtime
    module Waybar
      module_function

      def render(config_path, out: $stdout)
        config = Core::Config.load_config(config_path)
        snapshot = State.read_snapshot(config)
        out.puts(JSON.generate(payload(config, snapshot)))
      end

      def payload(config, snapshot, now = Time.now)
        unless snapshot
          return {
            text: "BB ...",
            tooltip: "BackupBar is waiting for its first telemetry snapshot.\nMiddle click: re-read sources",
            class: ["backupbar", "loading"]
          }
        end

        view = snapshot[:view] || {}
        chip = view[:chip] || {}
        classes = Array(chip[:classes]).uniq
        classes << "stale" if State.stale?(snapshot, config, now)
        {
          text: chip[:text] || "BB ...",
          tooltip: Array(chip[:tooltipLines]).join("\n"),
          class: classes.uniq
        }
      end

      def refresh(config_path)
        Daemon.refresh(config_path)
      end

      def open_panel(config_path)
        QuickShell.open(config_path)
      end
    end
  end
end
