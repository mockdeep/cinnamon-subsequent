# frozen_string_literal: true

require "ui/header"

RSpec.describe UI::Header do
  subject(:header) { described_class.new }

  def dropdowns = header.children.grep(UI::Dropdown)
  def board = dropdowns.first
  def lane = dropdowns.last
  def trailing = header.children.grep(Gtk::Box).first
  def buttons = trailing.children.grep(Gtk::Button)
  def refresh_button = buttons.first
  def collapse_button = buttons.last
  def spinner = trailing.children.grep(Gtk::Spinner).first

  def face_text(dropdown) = dropdown.child.children.grep(Gtk::Label).first.label
  def listbox(dropdown) = dropdown.popover.child.child.child

  let(:items) do
    [{ "id" => "a", "name" => "Apple" }, { "id" => "b", "name" => "Banana" }]
  end

  # Realize the widgets so show/hide visibility reads back reliably.
  before { header.show_all }

  describe "#set_boards / #set_lanes" do
    it "populates the board dropdown" do
      header.set_boards(items, "b")

      expect(face_text(board)).to eq("Banana")
    end

    it "populates the lane dropdown" do
      header.set_lanes(items, "a")

      expect(face_text(lane)).to eq("Apple")
    end
  end

  describe "#busy=" do
    it "locks the controls and swaps refresh for the spinner" do
      header.busy = true

      expect(board).not_to be_sensitive
      expect(lane).not_to be_sensitive
      expect(refresh_button).not_to be_visible
      expect(spinner).to be_visible
    end

    it "restores the controls when cleared" do
      header.busy = true
      header.busy = false

      expect(board).to be_sensitive
      expect(refresh_button).to be_visible
      expect(spinner).not_to be_visible
    end
  end

  describe "callbacks" do
    it "fires on_refresh when the refresh button is clicked" do
      fired = false
      header.on_refresh { fired = true }

      refresh_button.clicked

      expect(fired).to be(true)
    end

    it "fires on_collapse when the collapse button is clicked" do
      fired = false
      header.on_collapse { fired = true }

      collapse_button.clicked

      expect(fired).to be(true)
    end

    it "fires on_board_change when a board is chosen" do
      chosen = nil
      header.on_board_change { |id| chosen = id }
      header.set_boards(items, "a")

      listbox(board).signal_emit("row-activated", listbox(board).children[1])

      expect(chosen).to eq("b")
    end

    it "fires on_lane_change when a lane is chosen" do
      chosen = nil
      header.on_lane_change { |id| chosen = id }
      header.set_lanes(items, "a")

      listbox(lane).signal_emit("row-activated", listbox(lane).children[1])

      expect(chosen).to eq("b")
    end

    it "is a safe no-op when no callbacks are registered" do
      header.set_boards(items, "a")
      header.set_lanes(items, "a")

      expect do
        listbox(board).signal_emit("row-activated", listbox(board).children[1])
        listbox(lane).signal_emit("row-activated", listbox(lane).children[1])
        refresh_button.clicked
        collapse_button.clicked
      end.not_to raise_error
    end
  end
end
