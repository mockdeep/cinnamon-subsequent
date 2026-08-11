# frozen_string_literal: true

require "config"
require "trello_client"
require "board_fetch"
require "sync"
require "auto_refresh"
require "ui/header"
require "ui/dock_window"

# Wires the UI to Trello and drives the board → lane → checklist cascade.
# Every network call runs on a worker thread (via Sync) and renders its result
# back on the main thread; the header shows a busy spinner meanwhile.
class App
  def initialize(config, header: UI::Header.new, window: nil, client: nil, auto_refresh: nil)
    @config = config
    @header = header
    @window = window || build_window
    @client = client || build_client
    @auto_refresh = auto_refresh || AutoRefresh.new(interval: config.refresh_interval)
    @lane_view = nil
    @selected_tags = Set.new
    @item_limit = config.item_limit
    # Random mode starts off every launch (only its size is remembered), so a
    # cold start always shows the real list.
    @random = false
    @random_count = config.random_count
    @pick = nil
    wire_callbacks
    @window.item_limit = @item_limit
    @window.random_count = @random_count
  end

  def start
    @window.show_all
    @window.apply_dock_behaviour

    unless @client
      @window.render(empty(@config.setup_hint))
      return
    end

    load_boards
    @auto_refresh.start
  end

  # Push a fresh set of Claude sessions to the dock's footer dots. Driven by the
  # Sessions::Watcher poll loop, which is wired up in bin/todo-sidebar.
  def update_sessions(sessions, focused_xid)
    @window.set_sessions(sessions, focused_xid)
  end

  # Wire the dock's session-dot click to a focus action (the hook).
  def on_session_focus(&)
    @window.on_session_focus(&)
  end

  private

  def build_window
    UI::DockWindow.new(edge: @config.edge,
                       width: @config.width,
                       font_size: @config.font_size,
                       header: @header)
  end

  def build_client
    return false unless @config.configured?

    TrelloClient.new(key: @config.trello_key, token: @config.trello_token)
  end

  # Every user-facing callback goes through `interaction`, which both runs the
  # action and tells the auto-refresh clock the user is still here. That's the
  # whole guard against a background reload landing on a row mid-click.
  def wire_callbacks
    @header.on_board_change { |board_id| interaction { select_board(board_id) } }
    @header.on_lane_change  { |lane_id| interaction { select_lane(lane_id) } }
    @header.on_refresh      { interaction { refresh_view } }
    @window.on_item_toggle do |row, item, desired|
      interaction { toggle_item(row, item, desired) }
    end
    @window.on_tag_change   { |selected| interaction { select_tags(selected) } }
    @window.on_limit_change { |limit| interaction { select_limit(limit) } }
    @window.on_random_change do |random, count|
      interaction { select_random(random, count) }
    end
    @window.on_font_size_change { |size| interaction { select_font_size(size) } }
    @auto_refresh.on_refresh { refresh_quietly }
  end

  def interaction
    @auto_refresh.touch
    yield
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

  # User picked a different board → reset to its first lane. Its tags are a
  # different set, so the tag selection starts clean.
  def select_board(board_id)
    @selected_tags = Set.new
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

  # Switching lane brings up a different set of tags, so reset the selection.
  def select_lane(lane_id)
    @selected_tags = Set.new
    persist(@config.board_id, lane_id)
    fetch_and_render
  end

  # User toggled tag chips: re-render from the held lane view, no refetch.
  # The chips stay live in random mode, where they narrow what can be drawn —
  # so a click there deals a fresh hand from the new selection.
  def select_tags(selected)
    @selected_tags = selected.to_set
    reroll
    rerender
  end

  # The dice, or its count while it's on. Turning it on (or changing how many)
  # deals a new hand; turning it off drops back to the tag/cap view. The count
  # is persisted, the mode deliberately isn't.
  def select_random(random, count)
    @random = random
    if count != @random_count
      @random_count = count
      @config.random_count = count
      @config.save
    end
    reroll
    rerender
  end

  # User picked a new per-list cap: persist it and re-render from the held
  # lane view — the full item lists are still in memory, so no refetch.
  def select_limit(limit)
    @item_limit = limit
    @config.item_limit = limit
    @config.save
    rerender
  end

  # User stepped the text size: the window has already restyled itself, so this
  # only has to remember the choice for next launch.
  def select_font_size(size)
    @config.font_size = size
    @config.save
  end

  def rerender
    return unless @lane_view

    @window.render(@lane_view.result_for(@selected_tags, limit: @item_limit, ids: @pick))
  end

  # Draw a new random hand from the current selection. Held as item ids so the
  # pick survives the re-renders that don't deserve a re-roll (a cap change,
  # and — since ticking a row doesn't re-render — working through the list).
  def reroll
    @pick =
      if @random && @lane_view
        @lane_view.sample(@selected_tags, count: @random_count)
      end
  end

  # Reload the whole cascade (boards → lanes → cards) so the dropdowns
  # repopulate too — not just the leaf checklist. This also recovers a cold
  # start that failed offline, where boards/lanes never loaded. The persisted
  # board_id/lane_id keep the current selection. Unlike a board/lane switch,
  # refresh leaves @selected_tags intact, so the active tag filter survives
  # (finish_lane drops only tags that no longer exist).
  def refresh_view
    load_boards if @client
  end

  # The unattended refresh, fired by AutoRefresh once the sidebar has sat idle.
  # Deliberately cheaper and quieter than the Refresh button: one card fetch
  # rather than the full cascade (the dropdowns can't have changed while nobody
  # was touching them), no loading spinner over the list, and a failure that
  # leaves the current items alone.
  #
  # The exception is a sidebar that never got a lane — a cold start with no
  # network, or no board picked yet. There the loud cascade *is* the right move:
  # there's nothing on screen worth protecting, and it's the path that repopulates
  # the empty dropdowns. So an offline start now heals itself once you're back
  # online, without waiting for you to press Refresh.
  def refresh_quietly
    return unless @client

    @lane_view ? fetch_and_render(quiet: true) : load_boards
  end

  def fetch_and_render(quiet: false)
    @window.render_loading unless quiet
    busy(true)
    Sync.run(-> { BoardFetch.new(@client, @config).call },
             on_success: ->(lane_view) { finish_lane(lane_view) },
             on_error: quiet ? method(:log_error) : method(:show_error))
  end

  def persist(board_id, lane_id)
    @config.board_id = board_id
    @config.lane_id = lane_id
    @config.save
  end

  # A freshly fetched lane: populate the tag bar and render. The selection is
  # reconciled against the lane's actual tags — a refresh keeps every selection
  # that still exists; a reset (board/lane switch) has already emptied it.
  # Every fetch deals a fresh hand, so Refresh (and the idle auto-refresh) is
  # also how you ask random mode for something new.
  def finish_lane(lane_view)
    @lane_view = lane_view
    @selected_tags &= lane_view.tags.to_set(&:name)
    @window.set_tags(lane_view.tags, @selected_tags)
    reroll
    rerender
    busy(false)
  end

  # An empty/error state from the cascade (no boards, no lanes, Trello error):
  # no lane view, so clear any tags and render the plain message.
  def finish(result)
    @lane_view = nil
    @selected_tags = Set.new
    @pick = nil
    @window.set_tags([], @selected_tags)
    @window.render(result)
    busy(false)
  end

  def show_error(error)
    finish(empty("Trello error: #{error.message}"))
  end

  # A background refresh that failed (offline, Trello hiccup). Keep whatever is
  # on screen and let the next tick try again — wiping a usable list for an error
  # the user never asked for would be worse than showing a few stale items.
  def log_error(error)
    warn("Auto-refresh failed: #{error.message}")
    busy(false)
  end

  def busy(flag) = @header.busy = flag

  def empty(reason) = BoardFetch::Result.new(groups: [], empty_reason: reason)
end
