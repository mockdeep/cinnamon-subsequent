# frozen_string_literal: true

require "json"

module Sessions
  # Focuses a session's terminal by invoking the claude-session-tracker hook's
  # `focus` action — it raises the window with wmctrl and, when it can, switches
  # to the right Gnome Terminal tab. Runs off the GTK main thread: clicking a
  # dot shouldn't block the UI on a wmctrl/gdbus round-trip.
  module Focus
    # The hook lives in this repo's bin/, so resolve it by path rather than via
    # PATH (which is bare at login, when the sidebar autostarts).
    HOOK = File.expand_path("../../bin/claude-session-tracker", __dir__)

    def self.call(session_id, hook: HOOK, runner: method(:spawn))
      return if session_id.nil? || session_id.to_s.empty?

      Thread.new { runner.call(hook, JSON.dump(session_id: session_id)) }
    end

    def self.spawn(hook, payload)
      IO.popen([hook, "focus"], "w") { |io| io.write(payload) }
    rescue StandardError => e
      warn("Session focus failed: #{e.message}")
    end
  end
end
