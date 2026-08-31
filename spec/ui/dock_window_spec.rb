# frozen_string_literal: true

require "sessions/store"
require "ui/dock_window"
require "ui/header" # DockWindow takes a header but doesn't require it itself

RSpec.describe UI::DockWindow do
  subject(:dock) { described_class.new(header: UI::Header.new, width: 320) }

  def stack = dock.child
  def strip_count = dock.instance_variable_get(:@strip_count).label
  def checklist_view = dock.instance_variable_get(:@checklist_view)
  def tag_bar = dock.instance_variable_get(:@tag_bar)
  def limit_bar = dock.instance_variable_get(:@limit_bar)
  def session_box = dock.instance_variable_get(:@session_box)
  def strip_dots = dock.instance_variable_get(:@strip_dots)

  describe "#render" do
    it "shows the remaining-item count on the collapsed strip" do
      dock.render(
        make_result(
          groups: [
            make_group(items: [make_item, make_item(id: "i2")]),
          ],
        ),
      )

      expect(strip_count).to eq("2")
    end

    it "blanks the strip count when nothing remains" do
      dock.render(make_result(groups: [], empty_reason: "done"))

      expect(strip_count).to eq("")
    end

    it "counts items the per-list cap hid, not just the rendered ones" do
      group = make_group(
        items: [make_item, make_item(id: "i2")],
        hidden_count: 3,
      )

      dock.render(make_result(groups: [group]))

      expect(strip_count).to eq("5")
    end

    it "passes the toggle handler down to the rendered rows" do
      captured = nil
      dock.on_item_toggle { |*args| captured = args }
      dock.render(make_result(groups: [make_group]))

      row = checklist_view.child.child.children.grep(UI::ItemRow).first
      row.children.grep(Gtk::CheckButton).first.active = true

      expect(captured).to eq([row, row.item, "complete"])
    end
  end

  describe "#set_tags / #on_tag_change" do
    def tag(name, count) = BoardFetch::Tag.new(name: name, item_count: count)

    it "forwards tags to the tag bar" do
      dock.set_tags([tag("@home", 1)], Set.new)

      labels = tag_bar.children.map { |c| c.children.first.label }
      expect(labels).to eq(["@home (1)"])
    end

    it "relays a chip toggle to the on_tag_change handler" do
      captured = nil
      dock.on_tag_change { |selected| captured = selected }
      dock.set_tags([tag("@home", 1)], Set.new)
      dock.show_all

      tag_bar.children.first.children.first.active = true

      expect(captured).to eq(Set["@home"])
    end

    it "is a safe no-op to toggle a chip when no handler is wired" do
      dock.set_tags([tag("@home", 1)], Set.new)
      dock.show_all

      expect { tag_bar.children.first.children.first.active = true }
        .not_to raise_error
    end
  end

  describe "#item_limit= / #on_limit_change" do
    # The bar's dropdown list nests as popover > scroller > viewport > listbox.
    def limit_dropdown = limit_bar.children.grep(UI::Dropdown).first
    def limit_listbox = limit_dropdown.popover.child.child.child

    it "reflects a persisted limit on the limit bar's dropdown" do
      dock.item_limit = 3

      expect(limit_dropdown.active_id).to eq("3")
    end

    it "relays a dropdown choice to the on_limit_change handler" do
      captured = :unset
      dock.on_limit_change { |limit| captured = limit }

      # Row index 2 is the "2" entry ("All" is row 0).
      limit_listbox.signal_emit("row-activated", limit_listbox.children[2])

      expect(captured).to eq(2)
    end

    it "is a safe no-op to choose a limit when no handler is wired" do
      row = limit_listbox.children[1]

      expect { limit_listbox.signal_emit("row-activated", row) }
        .not_to raise_error
    end
  end

  describe "#random_count= / #on_random_change" do
    def dice = limit_bar.children.grep(Gtk::ToggleButton).first

    it "reflects a persisted pick size on the limit bar" do
      dock.random_count = 3

      expect(limit_bar.random_count).to eq(3)
    end

    it "relays the dice to the on_random_change handler, with the size" do
      captured = :unset
      dock.on_random_change { |random, count| captured = [random, count] }
      dock.random_count = 3

      dice.active = true

      expect(captured).to eq([true, 3])
    end

    it "is a safe no-op to press the dice when no handler is wired" do
      expect { dice.active = true }.not_to raise_error
    end
  end

  describe "#font_size= / #on_font_size_change" do
    def stepper(text)
      limit_bar.children.grep(Gtk::Button).find { |b| b.label == text }
    end

    it "starts at the size it was built with" do
      window = described_class.new(header: UI::Header.new, font_size: 17)

      expect(window.font_size).to eq(17)
      expect(window.instance_variable_get(:@limit_bar).font_size).to eq(17)
    end

    it "reflects a size set after construction on the footer steppers" do
      dock.font_size = 16

      expect(dock.font_size).to eq(16)
      expect(limit_bar.font_size).to eq(16)
    end

    it "does not fire the handler when the size is set programmatically" do
      captured = :unset
      dock.on_font_size_change { |size| captured = size }

      dock.font_size = 16

      expect(captured).to eq(:unset)
    end

    it "restyles and relays a stepper click to the handler" do
      captured = :unset
      dock.on_font_size_change { |size| captured = size }

      stepper("A+").signal_emit("clicked")

      expect(captured).to eq(14)
      expect(dock.font_size).to eq(14)
    end

    it "is a safe no-op to step the size when no handler is wired" do
      expect { stepper("A−").signal_emit("clicked") }.not_to raise_error
    end
  end

  describe "#render_loading" do
    it "shows the loading row in the content area" do
      dock.render_loading

      content = checklist_view.child.child.children.first
      expect(content.children.grep(Gtk::Spinner)).not_to be_empty
    end
  end

  describe "#collapse / #expand" do
    # show_all realizes the window so the real relayout has an XID.
    before { dock.show_all }

    it "swaps to the collapsed strip" do
      dock.collapse

      expect(stack.visible_child_name).to eq("collapsed")
    end

    it "stays collapsed when collapsed again" do
      dock.collapse
      dock.collapse

      expect(stack.visible_child_name).to eq("collapsed")
    end

    it "restores the expanded view" do
      dock.collapse
      dock.expand

      expect(stack.visible_child_name).to eq("expanded")
    end

    it "stays expanded when expanded while already expanded" do
      dock.expand

      expect(stack.visible_child_name).to eq("expanded")
    end
  end

  describe "#set_sessions / #on_session_focus" do
    def session(**overrides)
      Sessions::Session.new(
        id: "a",
        color: "#cc241d",
        status: "idle",
        project: "p",
        window_id: 1,
        **overrides,
      )
    end

    def footer_dots = session_box.children

    it "renders a dot per session in both the footer and the strip" do
      dock.set_sessions([session(id: "a"), session(id: "b", window_id: 2)], nil)

      expect(footer_dots.size).to eq(2)
      expect(strip_dots.children.size).to eq(2)
      expect(footer_dots).to all(be_a(UI::SessionDot))
    end

    it "hides the footer and strip when there are no sessions" do
      dock.show_all
      dock.set_sessions([], nil)

      expect(session_box).not_to be_visible
      expect(strip_dots).not_to be_visible
    end

    it "shows the footer once there are sessions" do
      dock.show_all
      dock.set_sessions([session], nil)

      expect(session_box).to be_visible
    end

    it "replaces the previous dots rather than appending" do
      dock.set_sessions([session(id: "a"), session(id: "b", window_id: 2)], nil)
      dock.set_sessions([session(id: "c")], nil)

      expect(footer_dots.size).to eq(1)
    end

    it "marks the dot whose window matches the focused xid as focused" do
      dock.set_sessions([session(id: "a", window_id: 5)], 5)

      expect(footer_dots.first.instance_variable_get(:@focused)).to be(true)
    end

    it "relays a footer dot click to the on_session_focus handler" do
      captured = nil
      dock.on_session_focus { |id| captured = id }
      dock.set_sessions([session(id: "abc")], nil)

      footer_dots.first.signal_emit("button-press-event", Gdk::EventButton.new(:button_press))

      expect(captured).to eq("abc")
    end
  end

  describe "#apply_dock_behaviour" do
    it "keeps below, sticks, and lays out without error" do
      dock.show_all

      expect { dock.apply_dock_behaviour }.not_to raise_error
    end
  end

  describe "#check_layout" do
    let(:rect)         { Struct.new(:x, :y, :width, :height) }
    let(:strut_writes) { []                                  }

    # A bottom panel's height is the thing that moves, so the workarea is held
    # in a hash the examples can edit mid-flight.
    let(:workarea) { { height: 1040 } }

    # A 1920x1080 monitor whose workarea is shortened by that panel.
    let(:panel_dock) do
      described_class.new(
        header: UI::Header.new,
        width: 320,
        geometry: lambda {
          [
            rect.new(0, 0, 1920, 1080),
            rect.new(0, 0, 1920, workarea[:height]),
            1920,
          ]
        },
      )
    end

    before do
      panel_dock.show_all # realize, so there's an XID to write a strut on
      allow(X11::Strut).to receive(:apply_right) { |_xid, **options| strut_writes << options }
      panel_dock.apply_dock_behaviour # settle at the starting layout
    end

    it "leaves the strut alone while the workarea stays put" do
      2.times { panel_dock.check_layout }

      expect(strut_writes.size).to eq(1) # only apply_dock_behaviour's
    end

    it "re-fits when a panel shrinks the workarea under it" do
      workarea[:height] = 1000

      panel_dock.check_layout

      expect(strut_writes.size).to eq(2)
      expect(strut_writes.last[:end_y]).to be < strut_writes.first[:end_y]
    end

    it "settles again once it has caught up with the new workarea" do
      workarea[:height] = 1000

      3.times { panel_dock.check_layout }

      expect(strut_writes.size).to eq(2)
    end

    it "does nothing before the window is realized" do
      unrealized = described_class.new(header: UI::Header.new, width: 320)

      expect { unrealized.check_layout }.not_to raise_error
    end
  end

  describe ".layout_for" do
    it "places the dock at the right edge and scales the strut to device px" do
      rect = Struct.new(:x, :y, :width, :height)

      layout = described_class.layout_for(
        monitor: rect.new(0, 0, 1920, 1080),
        workarea: rect.new(0, 27, 1920, 1053),
        screen_width: 1920,
        dock_width: 320,
        scale: 2,
      )

      expect(layout).to have_attributes(
        x: 1600,
        y: 27,
        width: 323,
        height: 1053,
        strut_width: 640,
        strut_start_y: 54,
        strut_end_y: 2159,
      )
    end
  end

  describe "#geometry" do
    it "returns the monitor rect, workarea, and screen width" do
      expect(dock.send(:geometry).size).to eq(3)
    end
  end
end
