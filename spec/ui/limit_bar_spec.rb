# frozen_string_literal: true

require "ui/limit_bar"

RSpec.describe UI::LimitBar do
  subject(:bar) { described_class.new { |limit| changes << limit } }

  let(:changes) { [] }

  def dropdown = bar.children.grep(UI::Dropdown).first
  def face_text = dropdown.child.children.grep(Gtk::Label).first.label
  # The dropdown list nests as popover > scroller > viewport > listbox.
  def listbox = dropdown.popover.child.child.child

  it "offers All plus 1-9, defaulting to All" do
    labels = listbox.children.map { |row| row.child.label }

    expect(labels).to eq(["All"] + ("1".."9").to_a)
    expect(face_text).to eq("All")
  end

  it "opens its popover upward, since the bar sits at the screen bottom" do
    expect(dropdown.popover.position).to eq(Gtk::PositionType::TOP)
  end

  describe "choosing a row" do
    it "reports a numeric choice as an Integer" do
      # Row index 3 is the "3" entry ("All" is row 0).
      listbox.signal_emit("row-activated", listbox.children.fetch(3))

      expect(changes).to eq([3])
    end

    it "reports All as nil" do
      listbox.signal_emit("row-activated", listbox.children.fetch(3))
      listbox.signal_emit("row-activated", listbox.children.first)

      expect(changes).to eq([3, nil])
    end
  end

  describe "#limit=" do
    it "shows a persisted cap without firing on_change" do
      bar.limit = 7

      expect(face_text).to eq("7")
      expect(changes).to be_empty
    end

    it "shows All for nil" do
      bar.limit = 7
      bar.limit = nil

      expect(face_text).to eq("All")
    end
  end

  it "tolerates being built without an on_change block" do
    plain = described_class.new
    rows = plain.children.grep(UI::Dropdown).first.popover.child.child.child

    expect { rows.signal_emit("row-activated", rows.children.fetch(2)) }
      .not_to raise_error
  end
end
