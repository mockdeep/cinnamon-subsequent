# frozen_string_literal: true

require "gtk3"
require "ui/dropdown"

module UI
  # Bottom bar holding the per-list item cap, the dice, and the text-size
  # steppers: a caption and a dropdown, then the ⚄ toggle and the A-/A+ buttons.
  # It sits flush against the screen bottom, so the dropdown's popover opens
  # upward.
  #
  # The caption and dropdown do double duty. Normally they are "Items per list"
  # over "All" or 1-9, reported as an Integer or nil for "All". With the dice
  # pressed they become "Random" over 1-9 — how many items to pick — and report
  # through on_random_change instead. The two values are held separately, so
  # turning the dice off restores the cap you had (and a cap of "All" leaves the
  # pick count at its default rather than meaning "all of them").
  class LimitBar < Gtk::Box
    COUNT_RANGE = (1..9)
    COUNTS = COUNT_RANGE.map { |n| { "id" => n.to_s, "name" => n.to_s } }.freeze
    CHOICES = ([{ "id" => "all", "name" => "All" }] + COUNTS).freeze

    DEFAULT_RANDOM_COUNT = 5

    # Stops for the A-/A+ steppers. Wide enough to be useful at either end —
    # they exist only so the buttons can't walk the sidebar down to unreadable
    # or up past the point where the topbar controls stop fitting.
    FONT_RANGE = (9..24)
    DEFAULT_FONT_SIZE = 13

    def initialize(
      font_size: DEFAULT_FONT_SIZE,
      random_count: DEFAULT_RANDOM_COUNT,
      on_font_change: nil,
      on_random_change: nil,
      &on_change
    )
      super(:horizontal, 6)
      style_context.add_class("limit-bar")
      @on_change = on_change
      @on_font_change = on_font_change
      @on_random_change = on_random_change
      @font_size = clamp(font_size)
      @random = false
      @random_count = clamp_count(random_count)
      @limit = nil

      @caption = Gtk::Label.new("")
      @caption.xalign = 0

      @dropdown = Dropdown.new(popover_position: :top) { |id| choose(id) }
      @dice = build_dice
      @smaller = build_step("A−", -1, "Smaller text")
      @bigger  = build_step("A+", +1, "Larger text")

      pack_start(@caption, expand: true, fill: true, padding: 0)
      # pack_end fills right-to-left in call order, so these read in reverse of
      # how they appear: dice, dropdown, A-, A+ along the bar.
      pack_end(@bigger, expand: false, fill: false, padding: 0)
      pack_end(@smaller, expand: false, fill: false, padding: 0)
      pack_end(@dropdown, expand: false, fill: false, padding: 0)
      pack_end(@dice, expand: false, fill: false, padding: 0)
      refresh_steps
      refresh_mode
    end

    attr_reader :font_size, :random_count

    # Whether the dice is pressed — i.e. the dropdown currently means "how many
    # to pick" rather than "cap each list at".
    def random? = @random

    # Point the dropdown at a persisted cap (nil = "All") without firing
    # on_change, so restoring the saved value doesn't trigger a re-render.
    def limit=(limit)
      @limit = limit
      refresh_mode unless @random
    end

    # Adopt a persisted pick size without firing on_random_change.
    def random_count=(count)
      @random_count = clamp_count(count)
      refresh_mode if @random
    end

    # Adopt a size set elsewhere (a persisted preference) without firing
    # on_font_change — it only updates which steppers are still available.
    def font_size=(size)
      @font_size = clamp(size)
      refresh_steps
    end

    private

    def build_dice
      button = Gtk::ToggleButton.new(label: "⚄")
      button.can_focus = false
      button.tooltip_text = "Pick items at random"
      button.style_context.add_class("dice")
      button.signal_connect("toggled") { toggle_random(button.active?) }
      button
    end

    def build_step(text, delta, tooltip)
      button = Gtk::Button.new(label: text)
      button.can_focus = false
      button.tooltip_text = tooltip
      button.style_context.add_class("font-step")
      button.signal_connect("clicked") { step(delta) }
      button
    end

    # A dropdown row: the same widget means the pick size or the cap, depending
    # on the dice.
    def choose(id)
      if @random
        @random_count = Integer(id, 10)
        @on_random_change&.call(true, @random_count)
      else
        @limit = (id == "all" ? nil : Integer(id, 10))
        @on_change&.call(@limit)
      end
    end

    # The dice: report the mode along with the count, since turning it on has
    # to deal a hand and the caller needs to know how big.
    def toggle_random(active)
      @random = active
      refresh_mode
      @on_random_change&.call(active, @random_count)
    end

    # Point the caption and dropdown at whichever value they currently stand
    # for. set_items assigns the active row without firing on_change, so
    # switching modes never looks like a user choice.
    def refresh_mode
      @caption.text = @random ? "Random" : "Items per list"
      if @random
        @dropdown.set_items(COUNTS, @random_count.to_s)
      else
        @dropdown.set_items(CHOICES, @limit ? @limit.to_s : "all")
      end
    end

    def step(delta)
      size = clamp(@font_size + delta)
      return if size == @font_size

      @font_size = size
      refresh_steps
      @on_font_change&.call(size)
    end

    # Grey out whichever stepper has nowhere left to go.
    def refresh_steps
      @smaller.sensitive = @font_size > FONT_RANGE.first
      @bigger.sensitive  = @font_size < FONT_RANGE.last
    end

    def clamp(size) = size.clamp(FONT_RANGE.first, FONT_RANGE.last)

    def clamp_count(count)
      return DEFAULT_RANDOM_COUNT unless count.is_a?(Integer)

      count.clamp(COUNT_RANGE.first, COUNT_RANGE.last)
    end
  end
end
