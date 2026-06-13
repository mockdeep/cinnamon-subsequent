# frozen_string_literal: true

require "gtk3"

module UI
  # One Claude session drawn as a filled circle in its terminal-theme color.
  # Permission state adds a white ring; the focused session gets a white inner
  # dot; an active (busy) session breathes — its alpha is animated by the owning
  # SessionBar. Cairo-drawn so we control alpha precisely (CSS opacity on a
  # styled box can't be tweened frame by frame).
  class SessionDot < Gtk::DrawingArea
    DEFAULT_SIZE = 16
    DEFAULT_COLOR = "#cc241d"

    attr_accessor :alpha

    def initialize(session, focused:, reactive: true, size: DEFAULT_SIZE)
      super()
      @session = session
      @focused = focused
      @alpha = 1.0
      set_size_request(size, size)
      self.tooltip_text = tooltip

      if reactive
        add_events(:button_press_mask)
        signal_connect("button-press-event") do
          @on_click&.call
          true
        end
      end
      signal_connect("draw") do |_widget, context|
        draw(context)
        false
      end
    end

    def on_click(&block) = @on_click = block

    def pulsing? = @session.active?

    private

    def draw(context)
      diameter = [allocated_width, allocated_height].min
      radius = (diameter / 2.0) - 2
      cx = allocated_width / 2.0
      cy = allocated_height / 2.0
      red, green, blue = rgb(@session.color)

      context.set_source_rgba(red, green, blue, @alpha)
      context.arc(cx, cy, radius, 0, 2 * Math::PI)
      context.fill

      if @session.permission?
        context.set_source_rgba(1, 1, 1, 0.95)
        context.line_width = 2
        context.arc(cx, cy, radius, 0, 2 * Math::PI)
        context.stroke
      end

      return unless @focused

      context.set_source_rgba(1, 1, 1, 0.95)
      context.arc(cx, cy, radius * 0.42, 0, 2 * Math::PI)
      context.fill
    end

    def tooltip
      "#{status_icon}#{@session.project}"
    end

    def status_icon
      case @session.status
      when "permission" then "⚠ "
      when "idle" then "❙❙ "
      else ""
      end
    end

    # Parse "#rrggbb" (the hook's prompt_fill) to [r, g, b] floats in 0..1,
    # falling back to the default color if it isn't a 6-digit hex string.
    def rgb(color)
      match = color.to_s.strip.match(/\A#?(\h{6})\z/)
      hex = match ? match[1] : DEFAULT_COLOR.delete("#")
      [0, 2, 4].map { |i| hex[i, 2].to_i(16) / 255.0 }
    end
  end
end
