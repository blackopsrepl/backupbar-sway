# frozen_string_literal: true

require_relative "test_helper"

class CollectorsTest < Minitest::Test
  def test_collects_existing_restic_anacron_and_systemd_shape
    Dir.mktmpdir do |root|
      restic_config = File.join(root, "backup.conf")
      anacron = File.join(root, ".anacrontab")
      borg_config = File.join(root, "borg-config.yaml")
      File.write(restic_config, <<~CONF)
        RESTIC_REPO="sftp:backup@example.invalid:/backup/repository"
        RESTIC_PASSWORD_FILE="$HOME/.config/backupbar/restic-password"
        BACKUP_PATHS=(
          "$HOME"
          "/workspace"
        )
      CONF
      File.write(anacron, "1 10 cron.backup ionice -c3 nice solverforge-backup\n7 20 cron.backup.prune ionice -c3 nice solverforge-backup-prune\n")
      File.write(borg_config, "repository:\n  path: /var/lib/backup-repository\nretention:\n  daily: 7\n  yearly: 1\n")
      config = temp_config(root)
      config[:source][:resticConfig] = restic_config
      config[:source][:userAnacron] = anacron
      config[:source][:borgConfig] = borg_config
      runner = FakeRunner.new

      raw = BackupBar::Core::Collectors.new(config, runner: runner).collect(now: Time.parse("2026-09-17T16:00:00Z"))
      restic = raw[:systems].find { |system| system[:id] == "restic" }
      borg = raw[:systems].find { |system| system[:id] == "borg" }

      assert_equal "healthy", restic[:status]
      assert_equal BackupBar::Core::Collectors::ICON_RESTIC, restic[:icon]
      assert_includes restic[:schedule], "daily via user anacron"
      assert_equal 2, restic.dig(:metrics, :pathCount)
      assert_equal "/var/lib/backup-repository", borg[:target]
      assert_equal BackupBar::Core::Collectors::ICON_BORG, borg[:icon]
      assert_equal "warning", borg[:status]
      assert raw[:storage].any?
    end
  end
end
