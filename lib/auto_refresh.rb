# frozen_string_literal: true

require "gtk3"

# Fires a callback once the sidebar has been left alone for `interval` seconds,
# then keeps firing every interval while it stays idle.
#
# Every user interaction calls #touch, which pushes the next fire out. That's
# what makes a background reload safe: it can never land on a row the user is
# mid-click on, because the click itself just reset the clock.
#
# The decision lives in #tick (pure, given a clock) so it's testable without a
# main loop; #start is the only GTK-facing part.
class AutoRefresh
  # How often we *check* whether the interval has elapsed. Much shorter than the
  # interval itself so the fire lands within half a minute of coming due,
  # rather than up to a whole interval late.
  TICK_MS = 30_000

  # CLOCK_BOOTTIME, not CLOCK_MONOTONIC: it can't be dragged around by NTP or a
  # timezone change, but unlike MONOTONIC it *does* count time the machine spent
  # suspended. So closing the lid overnight leaves the sidebar due on wake, and
  # it refreshes within a tick of opening it again.
  DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_BOOTTIME) }

  # `interval` is in seconds; nil or non-positive turns auto-refresh off.
  def initialize(interval:, clock: DEFAULT_CLOCK)
    @interval = interval
    @clock = clock
    @on_refresh = nil
    @last = clock.call
  end

  # Called when the idle interval elapses; the block takes no arguments.
  def on_refresh(&block) = @on_refresh = block

  # "The user just did something" — restart the idle countdown.
  def touch = @last = @clock.call

  # False when the config switched auto-refresh off, which makes every other
  # method here a no-op.
  def enabled? = @interval.is_a?(Numeric) && @interval.positive?

  # Start checking on a GLib timer. A no-op when disabled, so nothing polls at
  # all if auto-refresh is switched off in the config.
  def start
    return unless enabled?

    GLib::Timeout.add(TICK_MS) do
      tick
      true
    end
  end

  # One check. Touches before firing, so the next refresh is a full interval
  # after this one rather than immediately after.
  def tick
    return unless enabled?
    return if @clock.call - @last < @interval

    touch
    @on_refresh&.call
  end
end
