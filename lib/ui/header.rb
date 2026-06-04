# frozen_string_literal: true

require "gtk3"

module UI
  # Top bar: Board + Lane dropdowns and a Refresh button, plus a busy spinner.
  #
  # User-initiated selection fires the on_board_change / on_lane_change
  # callbacks. Programmatic population (set_boards/set_lanes) is suppressed so
  # the orchestrator can drive the board→lane→fetch cascade itself without the
  # combos re-triggering it.
  class Header < Gtk::Box
    def initialize
      super(:vertical, 6)
      style_context.add_class("topbar")
      self.margin = 12
      @suppress = false

      @board = combo { |id| @on_board_change&.call(id) }
      @lane  = combo { |id| @on_lane_change&.call(id) }

      @refresh = Gtk::Button.new(label: "Refresh")
      @refresh.can_focus = false
      @refresh.signal_connect("clicked") { @on_refresh&.call }

      @spinner = Gtk::Spinner.new
      @spinner.no_show_all = true

      action = Gtk::Box.new(:horizontal, 6)
      action.pack_start(@refresh, expand: false, fill: false, padding: 0)
      action.pack_end(@spinner, expand: false, fill: false, padding: 0)

      pack_start(@board, expand: false, fill: true, padding: 0)
      pack_start(@lane, expand: false, fill: true, padding: 0)
      pack_start(action, expand: false, fill: true, padding: 0)
    end

    def on_board_change(&block) = @on_board_change = block
    def on_lane_change(&block)  = @on_lane_change = block
    def on_refresh(&block)      = @on_refresh = block

    def set_boards(items, active_id) = populate(@board, items, active_id)
    def set_lanes(items, active_id)  = populate(@lane, items, active_id)

    # Toggle the busy state: spin and lock the controls during a fetch.
    def busy=(flag)
      @refresh.sensitive = !flag
      @board.sensitive = !flag
      @lane.sensitive = !flag
      if flag
        @spinner.show
        @spinner.start
      else
        @spinner.stop
        @spinner.hide
      end
    end

    private

    def combo
      box = Gtk::ComboBoxText.new
      box.can_focus = false
      box.signal_connect("changed") { yield(box.active_id) unless @suppress }
      box
    end

    def populate(combo, items, active_id)
      @suppress = true
      combo.remove_all
      items.each { |item| combo.append(item["id"], item["name"]) }
      combo.active_id = active_id if active_id
      @suppress = false
    end
  end
end
