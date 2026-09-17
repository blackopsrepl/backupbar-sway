# frozen_string_literal: true

require "json"

module BackupBar
  module CLI
    module_function

    def run(argv = ARGV)
      args = argv.dup
      command = args.shift || "help"
      options = parse_args(args)
      return 0 if options[:help]
      config_path = options[:config] || Core::Config.default_config_path

      case command
      when "config"
        run_config(options, config_path)
      when "daemon"
        snapshot = Runtime::Daemon.run(config_path, once: options[:once])
        print_json(snapshot, options) if options[:format] == "json" && options[:once]
        0
      when "refresh", "snapshot", "status"
        snapshot = Runtime::Daemon.refresh(config_path)
        print_json(snapshot, options) if options[:format] == "json" || command == "snapshot"
        0
      when "panel"
        Runtime::QuickShell.open(config_path)
        0
      when "ui"
        run_ui(options, config_path)
      when "waybar"
        run_waybar(options, config_path)
      when "help", "-h", "--help"
        puts usage
        0
      else
        raise ArgumentError, "Unknown command: #{command}"
      end
    rescue StandardError => e
      warn e.message
      1
    end

    def parse_args(argv)
      options = { format: "text", pretty: false, once: false, positionals: [] }
      index = 0
      while index < argv.length
        case argv[index]
        when "--config"
          index += 1
          raise ArgumentError, "--config requires a path" unless argv[index]

          options[:config] = argv[index]
        when "--format"
          index += 1
          raise ArgumentError, "--format requires text or json" unless %w[text json].include?(argv[index])

          options[:format] = argv[index]
        when "--pretty"
          options[:pretty] = true
        when "--once"
          options[:once] = true
        when "--help", "-h"
          options[:help] = true
        else
          raise ArgumentError, "Unknown option: #{argv[index]}" if argv[index].start_with?("-")

          options[:positionals] << argv[index]
        end
        index += 1
      end
      puts usage if options[:help]
      options
    end

    def run_config(options, config_path)
      subcommand = options[:positionals].first || "validate"
      if subcommand == "init"
        print_json(Core::Config.init_config(config_path), options)
        return 0
      end

      config = Core::Config.load_config(config_path, validate: false)
      issues = Core::Config.validate_config(config)
      if options[:format] == "json"
        print_json(issues, options)
      elsif issues.empty?
        puts "Config valid."
      else
        issues.each { |issue| puts "#{issue[:severity].upcase}: #{issue[:field]} #{issue[:message]}" }
      end
      issues.any? { |issue| issue[:severity] == "error" } ? 1 : 0
    end

    def run_ui(options, config_path)
      subcommand = options[:positionals].first || "status"
      payload = case subcommand
                when "open" then Runtime::QuickShell.open(config_path)
                when "close" then Runtime::QuickShell.close(config_path)
                when "toggle" then Runtime::QuickShell.toggle(config_path)
                when "status" then Runtime::QuickShell.status(config_path)
                else raise ArgumentError, "Unknown ui subcommand: #{subcommand}"
                end
      print_json(payload, options)
      0
    end

    def run_waybar(options, config_path)
      subcommand = options[:positionals].first || "render"
      case subcommand
      when "render" then Runtime::Waybar.render(config_path)
      when "refresh" then Runtime::Waybar.refresh(config_path)
      when "panel", "open" then Runtime::Waybar.open_panel(config_path)
      else raise ArgumentError, "Unknown waybar subcommand: #{subcommand}"
      end
      0
    end

    def print_json(payload, options)
      puts(options[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload))
    end

    def usage
      <<~TEXT
        BackupBar Linux

        Commands:
          backupbar config init|validate
          backupbar snapshot [--format json] [--pretty]
          backupbar refresh [--format json]
          backupbar status [--format json]
          backupbar daemon [--once]
          backupbar panel
          backupbar ui open|close|toggle|status
          backupbar waybar render|refresh|panel
      TEXT
    end
  end
end
