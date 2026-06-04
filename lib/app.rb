# frozen_string_literal: true

require "config"
require "trello_client"
require "board_fetch"
require "sync"
require "ui/header"
require "ui/dock_window"

# Wires the UI to Trello and drives the board → lane → checklist cascade.
# Every network call runs on a worker thread (via Sync) and renders its result
# back on the main thread; the header shows a busy spinner meanwhile.
class App
  def initialize(config)
    @config = config
    @client = config.configured? &&
              TrelloClient.new(key: config.trello_key, token: config.trello_token)
    @header = UI::Header.new
    @window = UI::DockWindow.new(edge: config.edge, width: config.width, header: @header)
    wire_callbacks
  end

  def start
    @window.show_all
    @window.apply_dock_behaviour

    unless @client
      @window.render(empty(@config.setup_hint))
      return
    end

    load_boards
  end

  private

  def wire_callbacks
    @header.on_board_change { |board_id| select_board(board_id) }
    @header.on_lane_change  { |lane_id| select_lane(lane_id) }
    @header.on_refresh      { refresh_view }
    @window.on_item_toggle  { |row, item, desired| toggle_item(row, item, desired) }
  end

  # Push a single item's new state to Trello; the row shows a spinner until
  # we settle or fail it. Doesn't touch the busy/refresh state — other rows
  # stay interactive while this one is in flight.
  def toggle_item(row, item, desired)
    complete = (desired == "complete")
    Sync.run(-> { @client.set_check_item_state(item.card_id, item.id, complete) },
             on_success: ->(_updated) { row.settle(desired) },
             on_error: ->(error) { row.fail(error) })
  end

  def load_boards
    @window.render_loading
    busy(true)
    Sync.run(-> { @client.boards },
             on_success: lambda do |boards|
               board_id = @config.board_id || boards.first&.dig("id")
               @header.set_boards(boards, board_id)
               if board_id
                 load_lanes(board_id, prefer_lane: @config.lane_id)
               else
                 finish(empty("No boards available."))
               end
             end,
             on_error: method(:show_error))
  end

  # User picked a different board → reset to its first lane.
  def select_board(board_id)
    load_lanes(board_id, prefer_lane: nil)
  end

  def load_lanes(board_id, prefer_lane:)
    @window.render_loading
    busy(true)
    Sync.run(-> { @client.lists(board_id) },
             on_success: lambda do |lanes|
               target = prefer_lane || lanes.first&.dig("id")
               @header.set_lanes(lanes, target)
               persist(board_id, target)
               if target
                 fetch_and_render
               else
                 finish(empty("This board has no lanes."))
               end
             end,
             on_error: method(:show_error))
  end

  def select_lane(lane_id)
    persist(@config.board_id, lane_id)
    fetch_and_render
  end

  def refresh_view
    fetch_and_render if @config.lane_id
  end

  def fetch_and_render
    @window.render_loading
    busy(true)
    Sync.run(-> { BoardFetch.new(@client, @config).call },
             on_success: ->(result) { finish(result) },
             on_error: method(:show_error))
  end

  def persist(board_id, lane_id)
    @config.board_id = board_id
    @config.lane_id = lane_id
    @config.save
  end

  def finish(result)
    @window.render(result)
    busy(false)
  end

  def show_error(error)
    finish(empty("Trello error: #{error.message}"))
  end

  def busy(flag) = @header.busy = flag

  def empty(reason) = BoardFetch::Result.new(groups: [], empty_reason: reason)
end
