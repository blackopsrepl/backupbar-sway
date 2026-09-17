# frozen_string_literal: true

require_relative "test_helper"

class StateTest < Minitest::Test
  def test_state_directory_and_files_are_private
    Dir.mktmpdir do |root|
      config = temp_config(root)
      snapshot = { snapshotVersion: 1, generatedAt: "2026-09-17T16:00:00Z", status: "healthy" }
      BackupBar::Runtime::State.write_snapshot(config, snapshot)

      assert_equal 0o700, File.stat(BackupBar::Runtime::State.state_dir(config)).mode & 0o777
      assert_equal 0o600, File.stat(BackupBar::Runtime::State.snapshot_path(config)).mode & 0o777
      assert_equal snapshot, BackupBar::Runtime::State.read_snapshot(config)
    end
  end

  def test_generated_timestamp_is_not_a_material_change
    first = { generatedAt: "2026-09-17T16:00:00Z", source: { queriedAt: "one" }, status: "healthy", view: { chip: { text: "BB 1/1" } } }
    second = { generatedAt: "2026-09-17T16:01:00Z", source: { queriedAt: "two" }, status: "healthy", view: { chip: { text: "BB 1/1" } } }

    refute BackupBar::Runtime::State.materially_changed?(first, second)
  end
end
