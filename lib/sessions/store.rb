# frozen_string_literal: true

require "json"

module Sessions
  # One Claude Code session as the sidebar needs to draw it: a colored dot with
  # a status, tied to the terminal window it was launched in. Built from the
  # per-session JSON the `claude-session-tracker` hook writes.
  Session =
    Struct.new(
      :id,
      :color,
      :status,
      :project,
      :window_id,
    ) do
      def active? = status == "active"
      def permission? = status == "permission"
    end

  # Reads the hook's per-session state files, reaping any whose process has
  # exited, and returns them as Session structs. This replaces the old Cinnamon
  # extension's directory poll — same files, same reaping rule: a session whose
  # pid no longer has a /proc entry is stale and its file is deleted.
  class Store
    DEFAULT_DIR = ENV.fetch(
      "CLAUDE_SESSION_STATE_DIR",
      File.join(Dir.home, ".local", "state", "claude-sessions"),
    )
    DEFAULT_COLOR = "#cc241d"

    def initialize(dir = DEFAULT_DIR, alive: method(:process_alive?))
      @dir = dir
      @alive = alive
    end

    # All live sessions, stale ones reaped, in a stable order so dots don't
    # jump around between polls (by window, then session id).
    def sessions
      files.filter_map { |file| load(file) }
           .sort_by { |session| [session.window_id || Float::INFINITY, session.id] }
    end

    private

    def files
      Dir.glob(File.join(@dir, "*.json"))
    rescue SystemCallError
      [] # directory gone or unreadable
    end

    def load(file)
      data = JSON.parse(File.read(file))
      return unless data["session_id"]

      pid = data["pid"]
      if pid && !@alive.call(pid)
        reap(file)
        return
      end

      to_session(data)
    rescue JSON::ParserError, SystemCallError
      nil # malformed, or vanished between glob and read — skip it
    end

    def to_session(data)
      theme = data["theme_color"]
      project = data["project_name"]
      Session.new(
        id: data["session_id"],
        color: blank?(theme) ? DEFAULT_COLOR : theme,
        status: data["status"] || "idle",
        project: blank?(project) ? "?" : project,
        window_id: window_id(data["window_id"]),
      )
    end

    # The hook writes window_id as a decimal X window id ($WINDOWID / xdotool);
    # parse it to an Integer so it compares with X11::ActiveWindow.current.
    def window_id(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def reap(file)
      File.delete(file)
    rescue SystemCallError
      nil # already gone — fine
    end

    def process_alive?(pid)
      File.directory?("/proc/#{pid}")
    end

    def blank?(value) = value.nil? || value.to_s.empty?
  end
end
