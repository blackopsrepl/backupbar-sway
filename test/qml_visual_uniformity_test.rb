# frozen_string_literal: true

require_relative "test_helper"

# Family-wide visual contract, shared by the *-bar panels under /srv/lab/tools
# (TokenMaxx's square-cornered aesthetic at Switchyard's font scale). Radii:
# zero on every shaped surface — frame, cards, buttons, tiles, rows, progress
# tracks and fills, the shadow band — with two pill/dot-family exemptions that
# are shapes, not corner rounding: the header live dot (7x7 at radius 3.5) and
# thin status stripes / heatcell bars (radius 1..2).
class QmlVisualUniformityTest < Minitest::Test
  QML_PATH = File.expand_path("../frontend/quickshell/shell.qml", __dir__)

  def qml
    @qml ||= File.read(QML_PATH)
  end

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
end
