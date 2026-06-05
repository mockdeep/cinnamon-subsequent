# frozen_string_literal: true

require "ui/dock_window"
require "ui/header" # DockWindow takes a header but doesn't require it itself

RSpec.describe UI::DockWindow do
  subject(:dock) { described_class.new(header: UI::Header.new, width: 320) }

  def stack = dock.child
  def strip_count = dock.instance_variable_get(:@strip_count).label
  def checklist_view = dock.instance_variable_get(:@checklist_view)

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

    it "passes the toggle handler down to the rendered rows" do
      captured = nil
      dock.on_item_toggle { |*args| captured = args }
      dock.render(make_result(groups: [make_group]))

      row = checklist_view.child.child.children.grep(UI::ItemRow).first
      row.children.grep(Gtk::CheckButton).first.active = true

      expect(captured).to eq([row, row.item, "complete"])
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

  describe "#apply_dock_behaviour" do
    it "keeps below, sticks, and lays out without error" do
      dock.show_all

      expect { dock.apply_dock_behaviour }.not_to raise_error
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
