# frozen_string_literal: true

require "gtk3"
require "ui/dropdown"

module UI
  # Top bar, all on one row: Board + Lane dropdowns share the width (ellipsizing
  # long names) and a compact refresh button sits at the end. While a fetch
  # runs, the refresh button is replaced in place by a spinner.
  #
  # The dropdowns are popover-based (see UI::Dropdown): only a real user
  # selection invokes on_board_change / on_lane_change, so populating them
  # programmatically never re-triggers the cascade.
  class Header < Gtk::Box
    def initialize
      super(:horizontal, 6)
      style_context.add_class("topbar")
      self.margin = 8

      @board = UI::Dropdown.new { |id| @on_board_change&.call(id) }
      @lane  = UI::Dropdown.new { |id| @on_lane_change&.call(id) }

      @refresh = Gtk::Button.new(label: "⟳")
      @refresh.can_focus = false
      @refresh.tooltip_text = "Refresh"
      @refresh.style_context.add_class("refresh")
      @refresh.signal_connect("clicked") { @on_refresh&.call }

      @spinner = Gtk::Spinner.new
      @spinner.no_show_all = true

      # Refresh and spinner share one trailing slot; only one shows at a time,
      # so the row's right edge stays put.
      trailing = Gtk::Box.new(:horizontal, 0)
      trailing.pack_start(@spinner, expand: false, fill: false, padding: 0)
      trailing.pack_start(@refresh, expand: false, fill: false, padding: 0)

      pack_start(@board, expand: true, fill: true, padding: 0)
      pack_start(@lane, expand: true, fill: true, padding: 0)
      pack_end(trailing, expand: false, fill: false, padding: 0)
    end

    def on_board_change(&block) = @on_board_change = block
    def on_lane_change(&block)  = @on_lane_change = block
    def on_refresh(&block)      = @on_refresh = block

    def set_boards(items, active_id) = @board.set_items(items, active_id)
    def set_lanes(items, active_id)  = @lane.set_items(items, active_id)

    # Toggle the busy state: lock the controls and swap refresh ↔ spinner.
    def busy=(flag)
      @board.sensitive = !flag
      @lane.sensitive = !flag
      @refresh.sensitive = !flag
      if flag
        @refresh.hide
        @spinner.show
        @spinner.start
      else
        @spinner.stop
        @spinner.hide
        @refresh.show
      end
    end
  end
end
