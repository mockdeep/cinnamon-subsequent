# frozen_string_literal: true

require "ui/tag_bar"

RSpec.describe UI::TagBar do
  subject(:bar) { described_class.new { |selected| changes << selected } }

  # Every on_change payload, newest last, so we can assert on the latest.
  let(:changes) { [] }

  # FlowBox wraps each child in a FlowBoxChild, so the toggle buttons are one
  # level down. Map back to the chips in insertion order.
  def chips = bar.children.map { |child| child.children.first }
  def chip(name) = chips.find { |c| c.label.start_with?(name) }

  def tag(name, count) = BoardFetch::Tag.new(name: name, item_count: count)

  # Realize the widget so visibility and toggle signals behave like the real UI.
  before { bar.show_all }

  describe "#set_tags" do
    it "renders one chip per tag, labelled with its count" do
      bar.set_tags([tag("@home", 2), tag("@work", 1)], Set.new)

      expect(chips.map(&:label)).to eq(["@home (2)", "@work (1)"])
    end

    it "makes the chips visible, not just present" do
      bar.set_tags([tag("@home", 2), tag("@work", 1)], Set.new)

      expect(chips).to all(be_visible)
    end

    it "starts chips pressed for the carried-over selection only" do
      bar.set_tags([tag("@home", 2), tag("@work", 1)], Set["@home"])

      expect(chip("@home")).to be_active
      expect(chip("@work")).not_to be_active
    end

    it "drops a carried-over selection that no longer exists" do
      bar.set_tags([tag("@work", 1)], Set["@home"])

      expect(bar.selected).to eq(Set.new)
    end

    it "does not fire on_change while repopulating a pressed selection" do
      bar.set_tags([tag("@home", 2)], Set["@home"])

      expect(changes).to be_empty
    end

    it "replaces the previous chips on a re-populate" do
      bar.set_tags([tag("@home", 2)], Set.new)
      bar.set_tags([tag("@work", 1)], Set.new)

      expect(chips.map(&:label)).to eq(["@work (1)"])
    end

    it "hides the bar when the lane has no tags" do
      bar.set_tags([tag("@home", 2)], Set.new)
      bar.set_tags([], Set.new)

      expect(bar).not_to be_visible
    end

    it "shows the bar once there are tags" do
      bar.set_tags([tag("@home", 2)], Set.new)

      expect(bar).to be_visible
    end
  end

  describe "toggling chips" do
    before { bar.set_tags([tag("@home", 2), tag("@work", 1)], Set.new) }

    it "adds a tag to the selection and reports it" do
      chip("@home").active = true

      expect(bar.selected).to eq(Set["@home"])
      expect(changes.last).to eq(Set["@home"])
    end

    it "accumulates multiple selected tags" do
      chip("@home").active = true
      chip("@work").active = true

      expect(changes.last).to eq(Set["@home", "@work"])
    end

    it "removes a tag when its chip is unpressed" do
      chip("@home").active = true
      chip("@home").active = false

      expect(bar.selected).to eq(Set.new)
      expect(changes.last).to eq(Set.new)
    end

    it "ignores a toggle when built without an on_change block" do
      plain = described_class.new
      plain.show_all
      plain.set_tags([tag("@home", 2)], Set.new)

      expect { plain.children.first.children.first.active = true }
        .not_to raise_error
    end
  end
end
