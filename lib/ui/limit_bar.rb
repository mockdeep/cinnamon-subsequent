# frozen_string_literal: true

require "gtk3"
require "ui/dropdown"

module UI
  # Bottom bar holding the per-list item cap: an "Items per list" label with a
  # dropdown offering "All" (no cap) or 1-9. It sits flush against the screen
  # bottom, so the dropdown's popover opens upward. Changes are reported as an
  # Integer cap, or nil for "All".
  class LimitBar < Gtk::Box
    CHOICES = ([{ "id" => "all", "name" => "All" }] +
               (1..9).map { |n| { "id" => n.to_s, "name" => n.to_s } }).freeze

    def initialize(&on_change)
      super(:horizontal, 6)
      style_context.add_class("limit-bar")

      label = Gtk::Label.new("Items per list")
      label.xalign = 0

      @dropdown = build_dropdown(on_change)
      @dropdown.set_items(CHOICES, "all")

      pack_start(label, expand: true, fill: true, padding: 0)
      pack_end(@dropdown, expand: false, fill: false, padding: 0)
    end

    # Point the dropdown at a persisted cap (nil = "All") without firing
    # on_change, so restoring the saved value doesn't trigger a re-render.
    def limit=(limit)
      @dropdown.active_id = limit ? limit.to_s : "all"
    end

    private

    def build_dropdown(on_change)
      Dropdown.new(popover_position: :top) do |id|
        on_change&.call(id == "all" ? nil : Integer(id, 10))
      end
    end
  end
end
