# frozen_string_literal: true

require "ui/dock_window"

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
    # relayout touches real Xlib; stub it. show_all so the stack tracks its
    # visible child by name.
    before do
      allow(dock).to receive(:relayout)
      dock.show_all
    end

    it "swaps to the collapsed strip and relays out once" do
      dock.collapse

      expect(stack.visible_child_name).to eq("collapsed")
      expect(dock).to have_received(:relayout).once
    end

    it "is idempotent when already collapsed" do
      dock.collapse
      dock.collapse

      expect(dock).to have_received(:relayout).once
    end

    it "restores the expanded view" do
      dock.collapse
      dock.expand

      expect(stack.visible_child_name).to eq("expanded")
    end

    it "does nothing when expand is called while already expanded" do
      dock.expand

      expect(dock).not_to have_received(:relayout)
    end
  end

  describe "#apply_dock_behaviour" do
    it "keeps the window below, sticks it, and lays out" do
      allow(dock).to receive(:relayout)
      allow(dock).to receive(:set_keep_below)
      allow(dock).to receive(:stick)

      dock.apply_dock_behaviour

      expect(dock).to have_received(:set_keep_below).with(true)
      expect(dock).to have_received(:stick)
      expect(dock).to have_received(:relayout)
    end
  end

  describe "#relayout (HiDPI strut math)" do
    it "converts logical px to device px by the scale factor" do
      geo = double("geometry", x: 0, width: 1920)
      workarea = double("workarea", x: 0, y: 27, width: 1920, height: 1053)
      gdk_window = double("gdk_window", xid: 99, scale_factor: 2)
      allow(dock).to receive(:geometry).and_return([geo, workarea, 1920])
      allow(dock).to receive(:window).and_return(gdk_window)
      allow(dock).to receive(:move)
      allow(dock).to receive(:set_size_request)
      allow(dock).to receive(:resize)
      allow(X11::Strut).to receive(:apply_right)

      dock.send(:relayout)

      # x = 0 + 1920 - 320; rendered width = 320 + EDGE_BLEED(3)
      expect(dock).to have_received(:move).with(1600, 27)
      expect(dock).to have_received(:resize).with(323, 1053)
      # right = (1920 - 1920 + 320) * 2; y-bounds * scale
      expect(X11::Strut).to have_received(:apply_right)
        .with(99, width: 640, start_y: 54, end_y: 2159)
    end
  end

  describe "#geometry" do
    it "returns the monitor rect, workarea, and screen width" do
      expect(dock.send(:geometry).size).to eq(3)
    end
  end
end
