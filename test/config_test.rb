# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults_keep_the_existing_user_anacron_contract
    config = BackupBar::Core::Config.default_config

    assert_equal 1, config[:version]
    assert_equal File.join(Dir.home, ".anacrontab"), config.dig(:source, :userAnacron)
    assert_equal 60, config.dig(:source, :refreshSeconds)
  end

  def test_normalization_rejects_unsafe_bounds
    config = BackupBar::Core::Config.normalize_config(source: { refreshSeconds: 1 }, display: { maxTimeline: 100 })

    fields = BackupBar::Core::Config.validate_config(config).map { |issue| issue[:field] }
    assert_includes fields, "source.refreshSeconds"
    assert_includes fields, "display.maxTimeline"
  end

  def test_config_round_trips_with_private_permissions
    Dir.mktmpdir do |root|
      path = File.join(root, "config.json")
      saved = BackupBar::Core::Config.save_config(BackupBar::Core::Config.default_config, path)

      assert_equal 1, saved[:version]
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 1, BackupBar::Core::Config.load_config(path)[:version]
    end
  end
end
