# frozen_string_literal: true

# Needs a display (Gtk.init) — runs under xvfb in CI.
require "ui/item_row"

RSpec.describe UI::ItemRow do
  def label(row) = row.children.grep(Gtk::Label).first
  def checkbox(row) = row.children.grep(Gtk::CheckButton).first
  def spinner(row) = row.children.grep(Gtk::Spinner).first

  describe "label markup (linkify/escape)" do
    it "escapes HTML-special characters in plain text" do
      row = described_class.new(make_item(name: "a < b & c > d"))

      expect(label(row).label).to eq("a &lt; b &amp; c &gt; d")
    end

    it "turns an http(s) word into a clickable (link), escaping the href" do
      row = described_class.new(make_item(name: "see http://x.com/a&b"))

      expect(label(row).label)
        .to eq('see (<a href="http://x.com/a&amp;b">link</a>)')
    end

    it "strikes through the label when the item is complete" do
      row = described_class.new(make_item(name: "done", state: "complete"))

      expect(label(row).label).to eq("<s>done</s>")
    end
  end

  describe "initial render" do
    it "checks the box and adds the done class for a complete item" do
      row = described_class.new(make_item(state: "complete"))

      expect(checkbox(row)).to be_active
      expect(row.style_context.has_class?("done")).to be(true)
    end

    it "leaves an incomplete item unchecked" do
      row = described_class.new(make_item(state: "incomplete"))

      expect(checkbox(row)).not_to be_active
      expect(row.style_context.has_class?("done")).to be(false)
    end
  end

  describe "user toggling the checkbox" do
    it "invokes on_toggle with the desired state and enters pending" do
      captured = nil
      row = described_class.new(
        make_item,
        on_toggle: lambda { |*args|
          captured = args
        },
      )
      row.show_all # so the spinner's visibility reads back once shown

      checkbox(row).active = true

      expect(captured).to eq([row, row.item, "complete"])
      expect(checkbox(row)).not_to be_sensitive
      expect(spinner(row)).to be_visible
    end

    it "adopts the new state itself when no orchestrator is wired" do
      row = described_class.new(make_item(state: "incomplete"))

      checkbox(row).active = true

      expect(row.item.state).to eq("complete")
    end

    it "reports an unchecked item as incomplete" do
      row = described_class.new(make_item(state: "complete"))

      checkbox(row).active = false

      expect(row.item.state).to eq("incomplete")
    end
  end

  describe "#settle" do
    it "adopts the state, leaves pending, and clears any failure" do
      row = described_class.new(make_item(state: "incomplete"))
      row.fail(StandardError.new("boom"))

      row.settle("complete")

      expect(row.item.state).to eq("complete")
      expect(checkbox(row)).to be_sensitive
      expect(spinner(row)).not_to be_visible
      expect(row.style_context.has_class?("failed")).to be(false)
      expect(row.tooltip_text).to be_nil
    end
  end

  describe "#fail" do
    it "reverts the checkbox and explains the error in the tooltip" do
      # on_toggle that doesn't settle, so the row stays pending (state unchanged)
      row = described_class.new(
        make_item(state: "incomplete"),
        on_toggle: lambda { |*|
        },
      )
      checkbox(row).active = true # user checked it; the push is now in flight

      row.fail(StandardError.new("no network"))

      expect(checkbox(row)).not_to be_active
      expect(row.style_context.has_class?("failed")).to be(true)
      expect(row.tooltip_text).to include("no network")
    end
  end
end
