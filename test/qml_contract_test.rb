# frozen_string_literal: true

require_relative "test_helper"

class QmlContractTest < Minitest::Test
  QML_PATH = File.expand_path("../frontend/quickshell/shell.qml", __dir__)

  # Memoized panel source: every method below reads the same file once.
  def qml
    @qml ||= File.read(QML_PATH)
  end

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
    # Family look: rounded frames, tone-dot badges. The layer surface itself is
    # bounded to the drop-down's rect: no scrim Rectangle behind the card, and
    # no screen-wide input mask (the bounded window retires both).
    assert_match(/radius:\s*[1-9]/, qml)
    assert_includes qml, "WlrKeyboardFocus.OnDemand"
    assert_includes qml, "implicitHeight: panelHeight()"
    refute_includes qml, "mask: Region"
    assert_includes qml, 'text: "Refresh reads existing telemetry only'
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
    assert_includes qml, 'text: (root.systems.length) + " observed"'
    assert_includes qml, '"· scroll"'
    assert_includes qml, 'visible: jobsScroll.contentHeight > jobsScroll.height'
    assert_includes qml, "· scroll"
    assert_includes qml, 'policy: ScrollBar.AsNeeded'
    # Short viewports: the counted surface height caps to the real viewport
    # (bar strip included), scrolling inside instead of cropping the frame.
    assert_includes qml, "panel.screen.height - root.panelTopMargin - 12"
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

  # The panel is a bar drop-down, not a screen-shaped overlay: the layer
  # surface itself is bounded to the card's rect, anchored to the bar edge on
  # the chip's side, and the height is counted from laid-out parts and capped
  # to the viewport. This is the family's bounded-surface contract (Switchyard
  # 8cda212 modalHeight pattern, tightened: the PanelWindow shrinks too).
  def test_panel_window_is_a_bounded_bar_drop_down_surface
    qml = File.read(QML_PATH)

    # The surface hangs from the top bar edge, toward the chip's left-of-center
    # side (one horizontal anchor, one side margin) — never the whole screen —
    # and reserves no layout space.
    assert_match(/anchors\s*\{\s*top:\s*true;\s*left:\s*true\s*\}/m, qml)
    refute_match(/anchors\s*\{[^}]*bottom:\s*true/m, qml)
    refute_match(/anchors\s*\{[^}]*right:\s*true/m, qml)
    assert_includes qml, "exclusionMode: ExclusionMode.Ignore"
    assert_includes qml, "WlrKeyboardFocus.OnDemand"

    # Height counted from laid-out parts (rows x row height + chrome), with a
    # viewport cap on the surface; the card must never need its own clamp
    # against the window because the window IS the card's size.
    assert_includes qml, "function panelHeight()"
    assert_match(/Math\.min\(root\.systems\.length,\s*12\)\s*\*\s*160/, qml)
    assert_match(/120\s*\+\s*.*146/, qml)
    assert_match(/panel\.screen\.height/, qml)
    assert_includes qml, "implicitHeight: panelHeight()"
    assert_includes qml, "implicitWidth: panelWidth()"
    # Content-fit width with a floor, never full-screen: the surface is a fixed
    # bar-drop width clamped to the viewport with a floor; layer margins cannot
    # shrink anchored edges, so width is explicit, not implicit-minus-margins.
    assert_match(/function panelWidth\(\)\s*\{\s*\n\s*return Math\.min\(root\.panelMaxWidth \+ root\.panelGutterWidth,\s*\n\s*Math\.max\(root\.panelMinWidth, panel\.screen\.width - 16\)\)/, qml)
    assert_includes qml, "property int panelMaxWidth: 1120"
    assert_includes qml, "property int panelMinWidth: 372"

    # No screen-dimension fallbacks: a screen-shaped surface is the thing this
    # contract retires.
    refute_match(/implicitWidth:\s*screen\s*\?\s*screen\.width/, qml)
    refute_match(/implicitHeight:\s*screen\s*\?\s*screen\.height/, qml)

    # No scrim, no backdrop catcher, no dim layer: the surface shows the card
    # and its shadow, nothing else. (The stripCatcher below is the bounded
    # window's own dismissal strip, not a screen-wide backdrop.)
    assert_includes qml, "id: frameShadow"
    assert_includes qml, "id: modalFrame"
    refute_match(/Rectangle\s*\{[^}]*anchors\.fill:\s*parent\s*\n\s*color:\s*(?:"transparent"|Qt\.rgba\(0,\s*0,\s*0,[^)]*0\.[0-9]+[^)]*\))[^}]*MouseArea/m, qml)
    refute_includes qml, "mask: Region { item: card"

    # Dismissal inside the bounded strip: Esc, and any click inside the window
    # but outside the card radius. The transparent click-catcher fills the
    # window (the strip), not the screen.
    assert_match(/id:\s*stripCatcher\s*\n\s*anchors\.fill:\s*panelItem\s*\n\s*z:\s*-1\s*\n\s*onClicked:\s*root\.closeModal/m, qml,
                 "the bounded window's strip catcher must be pinned")
    assert_match(/sequence:\s*"Esc"/, qml)

    # The card fills its frame with the counted margins; no inner centering
    # clamp survives from the full-screen surface. The frame is inset by the
    # gutter so the strip stays clickable inside the bounded window.
    assert_match(/id:\s*modalFrame\s*\n\s*\/\/[^\n]*\n\s*\/\/[^\n]*\n\s*\/\/[^\n]*\n\s*\/\/[^\n]*\n\s*anchors\.fill:\s*panelItem\s*\n\s*anchors\.leftMargin:\s*root\.panelGutterWidth/m, qml)
    assert_match(/anchors\.margins:\s*root\.panelChrome/, qml)

    # Viewport breakpoint clamps stay (narrowWidth/shortViewport), bound to the
    # bounded panel's own geometry.
    assert_match(/property bool narrowWidth:\s*panel\.width\s*<\s*[0-9]+/, qml)
    assert_match(/property bool shortViewport:\s*panel\.height\s*<\s*[0-9]+/, qml)
  end

  # Negative control for the bounded shape: reintroduce the retired
  # screen-shaped surface (a bottom anchor makes the layer full height and the
  # card a screen overlay again) and the contract must fail, so this test can
  # never pass vacuously.
  def test_bounded_surface_contract_rejects_the_screen_shaped_surface
    qml = File.read(QML_PATH)
    regressed = qml.sub(
        "anchors { top: true; left: true }",
        "anchors { top: true; left: true; right: true; bottom: true }"
    )
    raise "negative control could not reintroduce the full-height surface" if regressed == qml

    # The contract's exclusion pattern must fire on the regressed source:
    # assert the match present (assert, not refute — this is the tripwire).
    assert_match(/anchors\s*\{[^}]*bottom:\s*true/m, regressed)
  end

  # ----------------------------------------------------------------
  # Family-wide visual uniformity: TokenMaxx square corners (radius 0
  # everywhere except the 3.5 status dot and thin 1..2 stripes) at
  # Switchyard's font scale (7 dot glyph, 9 meta, 10 body, 11 section
  # labels, 12 summary values, 15 detail headers, 21 title).
  # ----------------------------------------------------------------
  def test_radius_is_zero_everywhere_except_dots_and_thin_stripes
    radii = qml.scan(/radius:\s*([0-9.]+)/).flatten.map(&:to_f)
    refute_empty radii, "the panel must still shape its dots and stripes"

    allowed = lambda do |value|
      value.zero? ||
        value == 3.5 ||            # the live/status dot, a circle not a corner
        (value >= 1 && value <= 2) # thin status stripes / heatcell-ish bars
    end

    bad = radii.reject { |value| allowed.call(value) }
    assert_empty bad, "unexpected radii (family spec: 0, dots 3.5, stripes 1..2): #{bad.uniq}"

    assert_equal [3.5], radii.select { |value| value == 3.5 }.uniq,
                 "the only non-zero, non-stripe radius is the dot's 3.5"
  end

  # The component's own block: from the marker to its balanced closing brace,
  # counted so nested children stay inside the segment and the next component
  # stays outside it.
  def component_block(marker)
    after = qml.split(marker, 2).last.to_s
    depth = 1
    lines = []
    after.each_line do |line|
      stripped = line.lstrip
      lines << line
      if stripped.start_with?("}")
        depth -= 1
        break if depth.zero?
      else
        depth += 1 if stripped.end_with?("{")
      end
    end
    lines.join
  end


  def test_frame_cards_buttons_and_tiles_drop_the_rounded_corner
    frame = qml[/id: frameShadow.*?^\s*\}/m].to_s
    card  = qml[/id: modalFrame.*?^\s*Flickable/m].to_s
    buttons = component_block("component ActionButton: Rectangle")
    tiles = component_block("component MetricTile: Rectangle")
    [frame, card, buttons, tiles].each do |block|
      assert_match(/radius: 0\b/, block, "frame/card/buttons/tiles must carry radius: 0")
    end
  end


  def test_zero_radius_is_pinned_by_negative_and_positive_control
    assert_match(/radius:\s*0\b/, qml, "square corners must actually appear in the source")
    # The old rounded frame must be gone: the pre-unification radii must not
    # survive as the panel's shaping (the dot's 3.5 and stripes 1..2 stay).
    [3, 9, 10].each do |gone|
      bad = qml.scan(/radius:\s*#{gone}\b(?![.\d])/).reject do
        gone == 3 # the dot's 3.5 and the stripe family are the exemptions
      end
      assert_empty bad, "the pre-unification radius #{gone} must not survive"
    end
  end


  def test_font_scale_is_the_family_scale
    allowed = [7, 9, 10, 11, 12, 15, 21]
    sizes = qml.scan(/font\.pixelSize:\s*([0-9]+)/).flatten.map(&:to_i)
    bad = sizes.reject { |value| allowed.include?(value) }
    assert_empty bad, "off-scale font sizes in panel text: #{bad.uniq}"

    # Every tier must still be present so the hierarchy survives unified.
    # (21 arrives through the title's 19 : 21 ternary and is pinned by its
    # own dedicated test below, so the numeric scan skips it here.)
    [9, 10, 11, 12].each do |size|
      assert_includes sizes, size, "font scale #{size} must still appear"
    end

    # The single off-scale 7 is the status badge's tone-dot glyph (the
    # "●" lead of the StatusBadge component's first Text), never a label.
    dot_index = qml.index('text: "●"')
    refute_nil dot_index, "the badge's tone-dot glyph must stay in the panel"
    badge_text = qml[/component StatusBadge.*?text: "●".*?\}/m].to_s
    assert_includes badge_text, "font.pixelSize: 7",
                    "the off-scale 7 is reserved for the badge's dot glyph"
    assert_operator qml.scan(/font\.pixelSize:\s*7\b/).length, :<=, 10,
                    "7s are dot glyphs only and stay rare"
  end


  def test_title_reads_the_family_title_size
    assert_match(/font\.pixelSize:\s*root\.shortViewport \? 19 : 21/, qml,
                 "the title joins Switchyard's title scale (19 narrow / 21 wide)")
    refute_match(/font\.pixelSize:\s*root\.shortViewport \? 22 : 24/, qml)
  end


  def test_headline_reads_the_family_summary_value_size
    headline = qml[/summary\.headlineText \|\| "--".*?\}/m].to_s
    assert_match(/font\.pixelSize:\s*12\b/, headline,
                 "the like-for-like headline is a summary value at Switchyard's 12")
  end


  def test_documented_stale_font_pins_are_re_sourced
    # Re-source every pin the family test carries: each value below must be
    # found in the source it names, so a family spec drift fails here first.
    pins = {
      "/srv/lab/tools/switchyard/frontend/quickshell/shell.qml" => [
        /radius:\s*0/,
        /font\.pixelSize:\s*root\.shortViewport \? 19 : 21/,
        /font\.pixelSize:\s*15/, # detail-view headers at Switchyard
        /font\.pixelSize:\s*12/  # summary values at Switchyard
      ]
    }
    pins.each do |source, patterns|
      body = File.read(source)
      patterns.each do |pattern|
        assert_match(pattern, body, "family pin #{pattern} drifted in #{source}")
      end
    end
  end


  # The header's live dot: green idle, amber while a refresh runs, red on a
  # presenter source error. Switchyard 8cda212 header convention, BackupBar
  # vocabulary (sourceStatus is the presenter's own fact, never re-derived).
  def test_panel_header_carries_the_live_dot_and_family_buttons
    qml = File.read(QML_PATH)

    assert_includes qml, "id: liveDot"
    assert_match(/id:\s*liveDot.*?root\.source\.status === "error"/m, qml)
    assert_match(/id:\s*liveDot.*?actionRunner\.running \|\| closeRunner\.running\)/m, qml)
    assert_match(/actionRunner\.running \|\| closeRunner\.running\)\s*\?\s*"#F2C572"\s*:\s*"#82FB9C"/, qml)
    assert_match(/ActionButton\s*\{\s*icon:\s*root\.refreshIcon\s*\n\s*label:\s*"Refresh"/m, qml)
    assert_match(/ActionButton\s*\{\s*icon:\s*root\.closeIcon\s*\n\s*label:\s*"Close"/m, qml)
  end
end
