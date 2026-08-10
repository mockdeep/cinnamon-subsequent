# frozen_string_literal: true

require "gtk3"
require "ui/dropdown"

module UI
  # Bottom bar holding the per-list item cap and the text-size steppers: an
  # "Items per list" label with a dropdown offering "All" (no cap) or 1-9, then
  # A-/A+ buttons that step the sidebar's base font size. It sits flush against
  # the screen bottom, so the dropdown's popover opens upward. Cap changes are
  # reported as an Integer, or nil for "All"; size changes as the new px size.
  class LimitBar < Gtk::Box
    CHOICES = ([{ "id" => "all", "name" => "All" }] +
               (1..9).map { |n| { "id" => n.to_s, "name" => n.to_s } }).freeze

    # Stops for the A-/A+ steppers. Wide enough to be useful at either end —
    # they exist only so the buttons can't walk the sidebar down to unreadable
    # or up past the point where the topbar controls stop fitting.
    FONT_RANGE = (9..24)
    DEFAULT_FONT_SIZE = 13

    def initialize(
      font_size: DEFAULT_FONT_SIZE,
      on_font_change: nil,
      &on_change
    )
      super(:horizontal, 6)
      style_context.add_class("limit-bar")
      @on_font_change = on_font_change
      @font_size = clamp(font_size)

      label = Gtk::Label.new("Items per list")
      label.xalign = 0

      @dropdown = build_dropdown(on_change)
      @dropdown.set_items(CHOICES, "all")
      @smaller = build_step("A−", -1, "Smaller text")
      @bigger  = build_step("A+", +1, "Larger text")

      pack_start(label, expand: true, fill: true, padding: 0)
      # pack_end fills right-to-left in call order, so these read in reverse of
      # how they appear: dropdown, then A-, then A+ along the bar.
      pack_end(@bigger, expand: false, fill: false, padding: 0)
      pack_end(@smaller, expand: false, fill: false, padding: 0)
      pack_end(@dropdown, expand: false, fill: false, padding: 0)
      refresh_steps
    end

    attr_reader :font_size

    # Point the dropdown at a persisted cap (nil = "All") without firing
    # on_change, so restoring the saved value doesn't trigger a re-render.
    def limit=(limit)
      @dropdown.active_id = limit ? limit.to_s : "all"
    end

    # Adopt a size set elsewhere (a persisted preference) without firing
    # on_font_change — it only updates which steppers are still available.
    def font_size=(size)
      @font_size = clamp(size)
      refresh_steps
    end

    private

    def build_dropdown(on_change)
      Dropdown.new(popover_position: :top) do |id|
        on_change&.call(id == "all" ? nil : Integer(id, 10))
      end
    end

    def build_step(text, delta, tooltip)
      button = Gtk::Button.new(label: text)
      button.can_focus = false
      button.tooltip_text = tooltip
      button.style_context.add_class("font-step")
      button.signal_connect("clicked") { step(delta) }
      button
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
  end
end
