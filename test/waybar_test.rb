# frozen_string_literal: true

require_relative "test_helper"

class WaybarTest < Minitest::Test
  def test_missing_snapshot_is_a_loading_chip
    payload = BackupBar::Runtime::Waybar.payload(BackupBar::Core::Config.default_config, nil)

    assert_equal "BB ...", payload[:text]
    assert_includes payload[:class], "loading"
  end

  def test_cached_snapshot_is_rendered_without_live_sources
    config = BackupBar::Core::Config.default_config
    snapshot = {
      status: "healthy",
      generatedAt: Time.now.utc.iso8601,
      view: { chip: { text: "BB 6/6", classes: ["backupbar", "healthy"], tooltipLines: ["healthy"] } }
    }

    payload = BackupBar::Runtime::Waybar.payload(config, snapshot)

    assert_equal "BB 6/6", payload[:text]
    assert_equal ["backupbar", "healthy"], payload[:class]
  end
end
