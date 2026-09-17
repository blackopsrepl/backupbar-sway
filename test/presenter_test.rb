# frozen_string_literal: true

require "time"
require_relative "test_helper"

class PresenterTest < Minitest::Test
  def test_attention_is_visible_in_chip_and_view
    config = BackupBar::Core::Config.default_config
    raw = {
      source: { status: "ok", queriedAt: "2026-09-17T16:00:00Z" },
      systems: [
        { id: "borg", label: "Borg", kind: "backup", status: "healthy", latestAt: "2026-09-17T15:50:00Z", latestText: "10m ago" },
        { id: "restic", label: "Restic", kind: "backup", status: "warning", latestAt: "2026-09-15T15:50:00Z", latestText: "2d ago" }
      ],
      storage: [],
      timeline: []
    }

    snapshot = BackupBar::Runtime::Presenter.apply(raw, config, now: Time.parse("2026-09-17T16:00:00Z"))

    assert_equal "warning", snapshot[:status]
    assert_equal 1, snapshot.dig(:summary, :attentionCount)
    assert_equal "BB 1/2", snapshot.dig(:view, :chip, :text)
    assert_includes snapshot.dig(:view, :chip, :classes), "attention"
  end
end
