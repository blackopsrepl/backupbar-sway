# frozen_string_literal: true

require_relative "test_helper"

class QmlContractTest < Minitest::Test
  def test_panel_uses_cached_state_and_exposes_no_backup_controls
    qml = File.read(File.expand_path("../frontend/quickshell/shell.qml", __dir__))

    assert_includes qml, "state-event.json"
    assert_includes qml, "BACKUP CONSTELLATION"
    assert_includes qml, "PRESSURE MAP"
    assert_includes qml, "Refresh reads existing telemetry only"
    assert_includes qml, "required property var modelData"
    assert_includes qml, "delegate: BackupCard {}"
    assert_includes qml, "delegate: StorageRow {}"
    assert_includes qml, "font.family: root.iconFont"
    assert_includes qml, "property string refreshIcon"
    assert_includes qml, "property string closeIcon"
    # Family look: rounded frames, tone-dot badges. Pins the mac-bar modal
    # contract (no scrim, no focus grab, card-bound input mask) too.
    assert_match(/radius:\s*[1-9]/, qml)
    assert_includes qml, "WlrKeyboardFocus.OnDemand"
    assert_includes qml, "mask: Region { item: card"
    refute_includes qml, "focusable: true"
    refute_includes qml, "solverforge-backup"
  end
end
