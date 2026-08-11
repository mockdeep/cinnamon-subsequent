# frozen_string_literal: true

require "ui/limit_bar"

RSpec.describe UI::LimitBar do
  subject(:bar) do
    described_class.new(
      font_size: font_size,
      random_count: random_count,
      on_font_change: ->(size) { sizes << size },
      on_random_change: ->(random, count) { rolls << [random, count] },
    ) { |limit| changes << limit }
  end

  let(:changes)      { []                                 }
  let(:sizes)        { []                                 }
  let(:rolls)        { []                                 }
  let(:font_size)    { 13                                 }
  let(:random_count) { UI::LimitBar::DEFAULT_RANDOM_COUNT }

  def dropdown = bar.children.grep(UI::Dropdown).first
  def face_text = dropdown.child.children.grep(Gtk::Label).first.label
  def caption   = bar.children.grep(Gtk::Label).first.label
  def dice      = bar.children.grep(Gtk::ToggleButton).first
  # The dropdown list nests as popover > scroller > viewport > listbox.
  def listbox = dropdown.popover.child.child.child
  def rows = listbox.children.map { |row| row.child.label }

  it "offers All plus 1-9, defaulting to All" do
    expect(rows).to eq(["All"] + ("1".."9").to_a)
    expect(face_text).to eq("All")
    expect(caption).to eq("Items per list")
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

  describe "the dice" do
    it "starts unpressed, with the bar in cap mode" do
      expect(dice).not_to be_active
      expect(bar).not_to be_random
    end

    it "reports the mode and the pick size when pressed" do
      dice.active = true

      expect(rolls).to eq([[true, 5]])
      expect(bar).to be_random
    end

    it "hands the dropdown over to the pick size, dropping All" do
      dice.active = true

      expect(caption).to eq("Random")
      expect(rows).to eq(("1".."9").to_a)
      expect(face_text).to eq("5")
    end

    it "reports a new pick size while it's on" do
      dice.active = true
      # Row index 2 is the "3" entry (the list starts at 1).
      listbox.signal_emit("row-activated", listbox.children.fetch(2))

      expect(rolls).to eq([[true, 5], [true, 3]])
      expect(changes).to be_empty
    end

    it "gives the dropdown back to the cap when switched off" do
      bar.limit = 4
      dice.active = true
      dice.active = false

      expect(rolls.last).to eq([false, 5])
      expect(caption).to eq("Items per list")
      expect(rows).to eq(["All"] + ("1".."9").to_a)
      expect(face_text).to eq("4")
    end

    it "leaves the pick size alone when the cap was All" do
      bar.limit = nil
      dice.active = true

      expect(face_text).to eq("5")
      expect(rolls).to eq([[true, 5]])
    end

    it "keeps a pick size chosen earlier across an off/on cycle" do
      dice.active = true
      listbox.signal_emit("row-activated", listbox.children.fetch(1))
      dice.active = false
      dice.active = true

      expect(face_text).to eq("2")
      expect(rolls.last).to eq([true, 2])
    end

    context "with a persisted pick size" do
      let(:random_count) { 8 }

      it "starts there once the dice goes on" do
        dice.active = true

        expect(face_text).to eq("8")
        expect(rolls).to eq([[true, 8]])
      end
    end

    describe "#random_count=" do
      it "adopts a persisted size without reporting it" do
        bar.random_count = 3

        expect(bar.random_count).to eq(3)
        expect(rolls).to be_empty
      end

      it "shows it straight away when the dice is already on" do
        dice.active = true
        bar.random_count = 3

        expect(face_text).to eq("3")
      end

      it "clamps a size the dropdown can't show" do
        bar.random_count = 99

        expect(bar.random_count).to eq(9)
      end

      it "falls back to the default for a non-integer" do
        bar.random_count = nil

        expect(bar.random_count).to eq(UI::LimitBar::DEFAULT_RANDOM_COUNT)
      end
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

  it "tolerates the dice with no on_random_change hook" do
    plain = described_class.new

    expect { plain.children.grep(Gtk::ToggleButton).first.active = true }
      .not_to raise_error
  end
end
