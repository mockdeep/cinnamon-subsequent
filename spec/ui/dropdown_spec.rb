# frozen_string_literal: true

require "ui/dropdown"

RSpec.describe UI::Dropdown do
  subject(:dropdown) { described_class.new { |id| changes << id } }

  let(:changes) { [] }
  let(:items) do
    [{ "id" => "a", "name" => "Apple" }, { "id" => "b", "name" => "Banana" }]
  end

  def face_text = dropdown.child.children.grep(Gtk::Label).first.label
  # MenuButton popover → ScrolledWindow → Viewport → ListBox.
  def listbox = dropdown.popover.child.child.child

  describe "#set_items" do
    it "populates the rows and shows the active item's name" do
      dropdown.set_items(items, "b")

      expect(listbox.children.size).to eq(2)
      expect(face_text).to eq("Banana")
    end

    it "does not invoke on_change (populating must not re-trigger the cascade)" do
      dropdown.set_items(items, "a")

      expect(changes).to be_empty
    end

    it "tolerates nil items" do
      dropdown.set_items(nil, nil)

      expect(listbox.children).to be_empty
      expect(face_text).to eq("")
    end
  end

  describe "#active_id=" do
    before { dropdown.set_items(items, "a") }

    it "blanks the label for an unknown id" do
      dropdown.active_id = "missing"

      expect(face_text).to eq("")
    end
  end

  describe "choosing a row" do
    before { dropdown.set_items(items, "a") }

    it "fires on_change and updates the active id for a new selection" do
      listbox.signal_emit("row-activated", listbox.children[1])

      expect(changes).to eq(["b"])
      expect(dropdown.active_id).to eq("b")
      expect(face_text).to eq("Banana")
    end

    it "ignores re-selecting the already-active row" do
      listbox.signal_emit("row-activated", listbox.children[0])

      expect(changes).to be_empty
    end

    it "ignores a row with no mapped id" do
      listbox.signal_emit("row-activated", Gtk::ListBoxRow.new)

      expect(changes).to be_empty
    end
  end

  it "tolerates being built without an on_change block" do
    plain = described_class.new
    plain.set_items(items, "a")
    rows = plain.popover.child.child.child

    expect { rows.signal_emit("row-activated", rows.children[1]) }
      .not_to raise_error
  end
end
