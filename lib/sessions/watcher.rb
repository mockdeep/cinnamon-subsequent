# frozen_string_literal: true

require "gtk3"
require "sessions/store"
require "x11/active_window"

module Sessions
  # Polls the session state directory and the active window on a GLib timer,
  # firing on_change only when the visible state actually changes. This is the
  # continuous loop the old Cinnamon extension ran; it's independent of the
  # sidebar's Trello side, which stays deliberately manual-refresh.
  class Watcher
    INTERVAL_MS = 1000

    def initialize(store: Store.new, active_window: X11::ActiveWindow)
      @store = store
      @active_window = active_window
      @on_change = nil
      @last_key = nil
    end

    def on_change(&block) = @on_change = block

    # Poll once now, then every INTERVAL_MS while the GTK main loop runs.
    def start
      tick
      GLib::Timeout.add(INTERVAL_MS) do
        tick
        true
      end
    end

    # One poll. Skips the callback when nothing the user would see changed, so
    # the pulse animation isn't reset and we don't rebuild dots every second
    # for nothing. The timestamp the hook bumps on every event is deliberately
    # excluded from the key.
    def tick
      sessions = @store.sessions
      focused = active_window
      key = [
        sessions.map do |s|
          [s.id, s.color, s.status, s.window_id]
        end,
        focused,
      ]
      return if key == @last_key

      @last_key = key
      @on_change&.call(sessions, focused)
    rescue StandardError => e
      warn("Session watcher error: #{e.message}")
    end

    private

    def active_window
      @active_window.current
    rescue StandardError
      nil # never let an X hiccup kill the poll loop
    end
  end
end
