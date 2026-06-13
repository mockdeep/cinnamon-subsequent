# frozen_string_literal: true

require "gtk3"
require "ui/session_dot"

module UI
  # Drives the session dots, rendering the same set into two sinks: the expanded
  # footer (a full-width Box where dots are evenly distributed) and the collapsed
  # strip (a thin column). Owns the pulse animation that breathes the active dots.
  # Not a widget itself: DockWindow builds the two sink containers and hands them in.
  class SessionBar
    PULSE_INTERVAL_MS = 80
    PULSE_MIN = 0.3
    PULSE_MAX = 0.95
    PULSE_STEP = 0.05
    STRIP_DOT_SIZE = 22

    def initialize(footer:, strip:, &on_focus)
      @footer = footer # Gtk::FlowBox in the expanded column
      @strip = strip   # Gtk::Box in the collapsed strip
      @on_focus = on_focus
      @dots = []
      @pulse_timer = nil
      @pulse_alpha = PULSE_MAX
      @pulse_direction = -1
    end

    # Rebuild both sinks from `sessions`; `focused_xid` lights the dot whose
    # terminal window is active. Hides both sinks when there are no sessions, so
    # the footer leaves no empty strip behind.
    def render(sessions, focused_xid)
      clear
      sessions.each do |session|
        focused = !session.window_id.nil? && session.window_id == focused_xid
        @dots << build_footer_dot(session, focused)
        @dots << build_strip_dot(session, focused)
      end
      sessions.empty? ? hide : show
      restart_pulse
    end

    private

    # expand + !fill gives each dot an equal slice of the footer width, centered
    # in its slice — the flexbox space-around distribution.
    def build_footer_dot(session, focused)
      dot = SessionDot.new(session, focused: focused)
      dot.on_click { @on_focus&.call(session.id) }
      @footer.pack_start(dot, expand: true, fill: false, padding: 0)
      dot
    end

    # Strip dots are display-only: the strip is one big button that expands on
    # click, so the dots stay non-reactive and let the click fall through.
    def build_strip_dot(session, focused)
      dot = SessionDot.new(
        session,
        focused: focused,
        reactive: false,
        size: STRIP_DOT_SIZE,
      )
      @strip.pack_start(dot, expand: false, fill: false, padding: 0)
      dot
    end

    def show
      @footer.show
      @footer.children.each(&:show_all)
      @strip.show
      @strip.children.each(&:show_all)
    end

    def hide
      @footer.hide
      @strip.hide
    end

    def clear
      stop_pulse
      @footer.children.each { |child| @footer.remove(child) }
      @strip.children.each { |child| @strip.remove(child) }
      @dots = []
    end

    def restart_pulse
      stop_pulse
      return if @dots.none?(&:pulsing?)

      @pulse_timer =
        GLib::Timeout.add(PULSE_INTERVAL_MS) do
          advance_pulse
          true
        end
    end

    def stop_pulse
      GLib::Source.remove(@pulse_timer) if @pulse_timer
      @pulse_timer = nil
    end

    # One frame of the breathing animation: bounce the shared alpha between the
    # bounds and repaint the active dots.
    def advance_pulse
      @pulse_alpha += @pulse_direction * PULSE_STEP
      if @pulse_alpha >= PULSE_MAX
        @pulse_alpha = PULSE_MAX
        @pulse_direction = -1
      elsif @pulse_alpha <= PULSE_MIN
        @pulse_alpha = PULSE_MIN
        @pulse_direction = 1
      end

      @dots.each do |dot|
        next unless dot.pulsing?

        dot.alpha = @pulse_alpha
        dot.queue_draw
      end
    end
  end
end
