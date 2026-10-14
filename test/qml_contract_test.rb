# frozen_string_literal: true

require_relative "test_helper"

class QmlContractTest < Minitest::Test
  QML_PATH = File.expand_path("../frontend/quickshell/shell.qml", __dir__)

  def read_only_commands(qml)
    # The panel's complete command surface: exactly two assignments, both
    # read-only. Anything concatenated into the args funnel or the close tail
    # makes a line differ from its pinned shape, so a mutation cannot hide
    # inside runBackupbar's own body either.
    allowed = [
      '[root.backupbarBin].concat(args).concat(["--config", root.configPath])',
      '[root.backupbarBin, "ui", "close", "--config", root.configPath]'
    ]
    assignments = qml.scan(/\.command\s*=\s*(.+)/).map { |(line)| line.strip }
    assignments.length == 2 && assignments.all? { |line| allowed.include?(line) }
  end

  def test_panel_uses_cached_state_and_exposes_no_backup_controls
    qml = File.read(QML_PATH)

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

  def test_panel_surfaces_dashboard_context_without_mutation_controls
    qml = File.read(QML_PATH)

    # Contextual dashboard: hidden facts made visible through the presenter's
    # projection. No metric is computed from a source here.
    assert_includes qml, "summary.headlineText"
    assert_includes qml, "context.nextRunText"
    assert_includes qml, "nextAtText"
    assert_includes qml, "repoUsageText"
    assert_includes qml, "overdue"
    # Like-for-like metric labels; singular/plural comes from the presenter.
    assert_match(/headlineText \|\|/, qml)
    # The job list must be count-labelled and show a scroll cue when content
    # overflows, and the main column must be a managed scroll with an
    # as-needed scrollbar (Switchyard's breakpoint pattern, BackupBar wording).
    assert_match(/property bool narrowWidth/, qml)
    assert_match(/property bool shortViewport/, qml)
    assert_includes qml, 'text: (root.systems.length) + " jobs"'
    assert_includes qml, '"· scroll"'
    assert_includes qml, 'visible: jobsScroll.contentHeight > jobsScroll.height'
    assert_includes qml, "· scroll"
    assert_includes qml, 'policy: ScrollBar.AsNeeded'
    # Negative control, run after the positive assertions: the panel's complete
    # CLI command surface is audited line by line and must stay read-only, and
    # no click handler may invoke a mutation verb. (A disclaimer may name the
    # verbs; a control may not.)
    assert_equal true, read_only_commands(qml)
    args_lists = qml.scan(/root\.runBackupbar\(\[(.*?)\]\)/).flatten.map(&:strip)
    assert_equal ['"refresh"'], args_lists.uniq
    qml.scan(/onClicked:\s*(.+)/).flatten.each do |action|
      %w[prune start stop unlock repair].each do |verb|
        refute_includes action, "\"#{verb}\""
      end
    end
    refute_includes qml, "--password"
  end

  def test_mutation_refusal_negative_control
    qml = File.read(QML_PATH)
    mutated = qml.sub(
      'actionRunner.command = [root.backupbarBin].concat(args).concat(["--config", root.configPath])',
      'actionRunner.command = [root.backupbarBin].concat(args).concat(["prune"]).concat(["--config", root.configPath])'
    )
    raise "negative control could not inject a mutation into the QML text" if mutated == qml

    assert_equal false, read_only_commands(mutated)
  end
end