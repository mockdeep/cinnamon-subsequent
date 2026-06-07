# frozen_string_literal: true

require "ui/checklist_view"

RSpec.describe UI::ChecklistView do
  subject(:view) { described_class.new }

  # ScrolledWindow auto-wraps its child in a Viewport, so the content box is
  # two levels down.
  def rows = view.child.child.children

  describe "#render" do
    it "shows a single empty-state label when there are no groups" do
      view.render(make_result(groups: [], empty_reason: "all done"))

      expect(rows.map(&:class)).to eq([Gtk::Label])
      expect(rows.first.label).to eq("all done")
    end

    it "falls back to a default message when no reason is given" do
      view.render(make_result(groups: [], empty_reason: nil))

      expect(rows.first.label).to eq("Nothing here.")
    end

    it "renders a header, an item row per item, and a spacer per group" do
      group = make_group(
        name: "List A",
        items: [
          make_item,
          make_item(id: "i2"),
        ],
      )

      view.render(make_result(groups: [group]))

      expect(rows.map(&:class))
        .to eq([Gtk::Label, UI::ItemRow, UI::ItemRow, Gtk::Box])
      expect(rows.first.label).to eq("List A")
    end

    it "replaces previous content on re-render" do
      view.render(make_result(groups: [make_group]))
      view.render(make_result(groups: [], empty_reason: "now empty"))

      expect(rows.map(&:class)).to eq([Gtk::Label])
    end

    it "leaves the header a bare label when the group has no links" do
      view.render(make_result(groups: [make_group(name: "List A")]))

      expect(rows.first).to be_a(Gtk::Label)
      expect(rows.first.label).to eq("List A")
    end

    it "adds an 'Open links (N)' button counting every URL occurrence" do
      group = make_group(
        items: [
          make_item(name: "see http://a.test and http://b.test"),
          make_item(id: "i2", name: "also http://a.test"),
        ],
      )

      view.render(make_result(groups: [group]))

      expect(rows.first).to be_a(Gtk::Box)
      button = rows.first.children.grep(Gtk::Button).first
      expect(button.label).to eq("Open links (3)")
    end

    it "launches every URL in document order when the button is clicked" do
      opened = []
      allow(Gio::AppInfo).to receive(:launch_default_for_uri) { |uri, _| opened << uri }
      group = make_group(
        items: [
          make_item(name: "see http://a.test and http://b.test"),
          make_item(id: "i2", name: "also http://a.test"),
        ],
      )

      view.render(make_result(groups: [group]))
      rows.first.children.grep(Gtk::Button).first.clicked

      expect(opened).to eq(["http://a.test", "http://b.test", "http://a.test"])
    end

    it "wires on_toggle through to its item rows" do
      captured = nil
      view.render(
        make_result(groups: [make_group]),
        on_toggle: ->(*args) { captured = args },
      )

      item_row = rows.grep(UI::ItemRow).first
      item_row.children.grep(Gtk::CheckButton).first.active = true

      expect(captured).to eq([item_row, item_row.item, "complete"])
    end
  end

  describe "#render_loading" do
    it "shows a spinner and a loading label" do
      view.render_loading

      row = rows.first
      expect(row.children.grep(Gtk::Spinner)).not_to be_empty
      expect(row.children.grep(Gtk::Label).first.label).to eq("Loading…")
    end
  end
end
