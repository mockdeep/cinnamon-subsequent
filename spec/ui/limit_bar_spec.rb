# frozen_string_literal: true

require "ui/limit_bar"

RSpec.describe UI::LimitBar do
  subject(:bar) do
    described_class.new(
      font_size: font_size,
      on_font_change: ->(size) { sizes << size },
    ) { |limit| changes << limit }
  end

  let(:changes)   { [] }
  let(:sizes)     { [] }
  let(:font_size) { 13 }

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

  describe "the A- / A+ steppers" do
    def smaller = bar.children.grep(Gtk::Button).find { |b| b.label == "A−" }
    def bigger  = bar.children.grep(Gtk::Button).find { |b| b.label == "A+" }

    it "steps the size down and reports the new one" do
      smaller.signal_emit("clicked")

      expect(sizes).to eq([12])
      expect(bar.font_size).to eq(12)
    end

    it "steps the size up and reports the new one" do
      bigger.signal_emit("clicked")

      expect(sizes).to eq([14])
    end

    context "when already at the bottom of the range" do
      let(:font_size) { UI::LimitBar::FONT_RANGE.first }

      it "disables the smaller stepper and reports nothing further" do
        expect(smaller).not_to be_sensitive

        smaller.signal_emit("clicked")

        expect(sizes).to be_empty
        expect(bar.font_size).to eq(UI::LimitBar::FONT_RANGE.first)
      end
    end

    context "when already at the top of the range" do
      let(:font_size) { UI::LimitBar::FONT_RANGE.last }

      it "disables the bigger stepper and reports nothing further" do
        expect(bigger).not_to be_sensitive

        bigger.signal_emit("clicked")

        expect(sizes).to be_empty
      end
    end

    it "clamps a size that was hand-edited out of range" do
      bar.font_size = 99

      expect(bar.font_size).to eq(UI::LimitBar::FONT_RANGE.last)
      expect(bigger).not_to be_sensitive
    end

    it "re-enables a stepper once the size moves off its stop" do
      bar.font_size = UI::LimitBar::FONT_RANGE.first
      bar.font_size = UI::LimitBar::FONT_RANGE.first + 1

      expect(smaller).to be_sensitive
    end
  end

  describe "#font_size=" do
    it "adopts a persisted size without firing on_font_change" do
      bar.font_size = 17

      expect(bar.font_size).to eq(17)
      expect(sizes).to be_empty
    end
  end

  it "tolerates being built without an on_change block" do
    plain = described_class.new
    rows = plain.children.grep(UI::Dropdown).first.popover.child.child.child

    expect { rows.signal_emit("row-activated", rows.children.fetch(2)) }
      .not_to raise_error
  end

  it "tolerates a stepper click with no on_font_change hook" do
    plain = described_class.new
    step = plain.children.grep(Gtk::Button).find { |b| b.label == "A+" }

    expect { step.signal_emit("clicked") }.not_to raise_error
  end
end
