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
