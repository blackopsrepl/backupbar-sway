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

  def test_view_exposes_per_job_backup_age_next_run_and_overdue
    config = BackupBar::Core::Config.default_config
    now = Time.parse("2026-09-17T16:00:00Z")
    raw = {
      source: { status: "ok", queriedAt: "2026-09-17T16:00:00Z" },
      systems: [
        {
          id: "borg", label: "Borg", kind: "backup", status: "healthy",
          latestAt: "2026-09-17T15:50:00Z", latestText: "10m ago",
          nextAt: "2026-09-17T16:47:00Z", metrics: { repoUsageText: "165.61 GB" }
        },
        {
          id: "restic", label: "Restic", kind: "backup", status: "warning",
          latestAt: "2026-09-15T15:50:00Z", latestText: "2d ago",
          nextAt: nil, metrics: { repoUsageText: "141.57 GB" }
        },
        { id: "snapper", label: "Snapper", kind: "rollback", status: "healthy", latestAt: "2026-09-17T15:30:00Z", latestText: "30m ago" }
      ],
      storage: [],
      timeline: []
    }

    snapshot = BackupBar::Runtime::Presenter.apply(raw, config, now: now)
    view = snapshot[:view]
    borg = view[:systems].find { |system| system[:id] == "borg" }
    restic = view[:systems].find { |system| system[:id] == "restic" }

    assert_equal "in 47m", borg[:nextAtText]
    assert_equal false, borg[:overdue]
    assert_equal true, restic[:overdue]
    assert_equal "165.61 GB", borg[:repoUsageText]
    assert_equal 1, view.dig(:summary, :overdueCount)
    assert_equal "in 47m", view.dig(:context, :nextRunText)
  end

  def test_summary_headline_is_like_for_like_with_singular_plural
    config = BackupBar::Core::Config.default_config
    now = Time.parse("2026-09-17T16:00:00Z")
    raw = {
      source: { status: "ok", queriedAt: "2026-09-17T16:00:00Z" },
      systems: [
        { id: "borg", label: "Borg", kind: "backup", status: "healthy", latestAt: "2026-09-17T15:50:00Z", latestText: "10m ago" }
      ],
      storage: [],
      timeline: []
    }

    snapshot = BackupBar::Runtime::Presenter.apply(raw, config, now: now)

    assert_equal "1 system / 0 overdue", snapshot.dig(:view, :summary, :headlineText)

    raw[:systems] << { id: "restic", label: "Restic", kind: "backup", status: "warning", latestAt: "2026-09-15T15:50:00Z", latestText: "2d ago" }
    snapshot = BackupBar::Runtime::Presenter.apply(raw, config, now: now)

    assert_equal "2 systems / 1 overdue", snapshot.dig(:view, :summary, :headlineText)
  end

  def test_context_reports_the_earliest_upcoming_run
    config = BackupBar::Core::Config.default_config
    now = Time.parse("2026-09-17T16:00:00Z")
    raw = {
      source: { status: "ok", queriedAt: "2026-09-17T16:00:00Z" },
      systems: [
        { id: "borg", label: "Borg", kind: "backup", status: "healthy", latestAt: "2026-09-17T15:50:00Z", nextAt: "2026-09-17T18:00:00Z" },
        { id: "secrets", label: "Secrets", kind: "backup", status: "healthy", latestAt: "2026-09-17T15:20:00Z", nextAt: "2026-09-17T16:35:00Z" },
        { id: "restic", label: "Restic", kind: "backup", status: "healthy", latestAt: "2026-09-17T15:10:00Z" }
      ],
      storage: [],
      timeline: []
    }

    snapshot = BackupBar::Runtime::Presenter.apply(raw, config, now: now)

    assert_equal "in 35m", snapshot.dig(:view, :context, :nextRunText)
  end
end