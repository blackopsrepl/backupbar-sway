# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "backupbar"

class FakeStatus
  def initialize(success = true, exitstatus = 0)
    @success = success
    @exitstatus = exitstatus
  end

  def success?
    @success
  end

  attr_reader :exitstatus
end

class FakeRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def run_command(command, args = [], timeout: 10, env: {})
    @calls << { command: command, args: args, timeout: timeout, env: env }
    stdout = case command
             when "systemctl"
               unit = args[1].to_s
               if unit.end_with?(".timer")
                 "ActiveState=active\nSubState=waiting\nResult=success\nLastTriggerUSec=Thu 2026-09-17 12:00:00 UTC\nNextElapseUSecRealtime=Thu 2026-09-18 12:00:00 UTC\n"
               else
                 "ActiveState=inactive\nSubState=dead\nResult=success\nExecMainStatus=0\nExecMainExitTimestamp=Thu 2026-09-17 12:01:00 UTC\n"
               end
             when "restic"
               if args.include?("--tag")
                 JSON.generate([
                   { "time" => "2026-09-16T23:20:06Z", "tags" => ["solverforge-secrets"], "paths" => ["/solverforge-secrets/service-secrets.tar"] }
                 ])
               else
                 JSON.generate([
                    { "time" => "2026-09-17T15:25:12Z", "tags" => [], "paths" => ["/example/home", "/example/data"] }
                 ])
               end
             when "df"
               "Filesystem 1B-blocks Used Available Capacity Mounted on\n/dev/test 1000000 800000 200000 80% /\n"
             when "sudo"
               args.include?("info") ? "All archives: 11.02 TB 7.05 TB 141.57 GB\n" : "1\n2\n"
             else
               ""
             end
    CoreResult.new(status: FakeStatus.new, stdout: stdout, stderr: "", timed_out: false)
  end

  CoreResult = Struct.new(:status, :stdout, :stderr, :timed_out) do
    def success?
      !timed_out && status.success?
    end
  end
end

module TestSupport
  def temp_config(root)
    config = BackupBar::Core::Config.default_config
    config[:runtime][:stateDir] = File.join(root, "state")
    config[:runtime][:quickShellShell] = File.join(root, "shell.qml")
    BackupBar::Core::Config.normalize_config(config)
  end
end

class Minitest::Test
  include TestSupport
end
