# frozen_string_literal: true

require "gtk3"
require "ui/links"

module UI
  # One checklist item with a small state machine:
  #
  #   synced ──click──▶ pending (spinner, checkbox locked)
  #     ▲                   │
  #     │            success│        failure
  #     └────────── settle ◀┘──▶ failed (revert + retry on next click)
  #
  # The row never talks to Trello itself; clicking invokes the on_toggle
  # callback, and the orchestrator calls back settle/fail with the outcome.
  # Completed items stay visible (checked + struck-through) and are undoable;
  # they only disappear on the next refresh, which refetches incomplete-only.
  class ItemRow < Gtk::Box
    attr_reader :item

    def initialize(item, on_toggle: nil)
      super(:horizontal, 8)
      @item = item
      @on_toggle = on_toggle
      @suppress = false
      style_context.add_class("item-row")

      @check = Gtk::CheckButton.new
      @check.can_focus = false
      pack_start(@check, expand: false, fill: false, padding: 0)

      @label = Gtk::Label.new
      @label.xalign = 0
      @label.wrap = true
      @label.wrap_mode = :word_char
      pack_start(@label, expand: true, fill: true, padding: 0)

      @spinner = Gtk::Spinner.new
      @spinner.no_show_all = true
      pack_end(@spinner, expand: false, fill: false, padding: 0)

      apply_state(@item.state)
      @check.signal_connect("toggled") { on_user_toggle unless @suppress }
    end

    # Network write confirmed: adopt the new state for good.
    def settle(state)
      @item.state = state
      stop_pending
      apply_state(state)
      style_context.remove_class("failed")
      self.tooltip_text = nil
    end

    # Network write failed: revert the checkbox and offer a retry on next click.
    def fail(error)
      suppressed { @check.active = (@item.state == "complete") }
      stop_pending
      style_context.add_class("failed")
      self.tooltip_text = "Couldn't reach Trello: #{error.message}. Click to retry."
    end

    private

    def on_user_toggle
      desired = @check.active? ? "complete" : "incomplete"
      start_pending
      if @on_toggle
        @on_toggle.call(self, @item, desired)
      else
        settle(desired) # no orchestrator wired (e.g. tests): just adopt it
      end
    end

    def apply_state(state)
      complete = (state == "complete")
      suppressed { @check.active = complete }
      markup = linkify(@item.name)
      @label.markup = complete ? "<s>#{markup}</s>" : markup
      complete ? style_context.add_class("done") : style_context.remove_class("done")
    end

    def start_pending
      @check.sensitive = false
      @spinner.show
      @spinner.start
    end

    def stop_pending
      @spinner.stop
      @spinner.hide
      @check.sensitive = true
    end

    # Run a block with the "toggled" handler muted, so programmatic checkbox
    # changes don't re-enter on_user_toggle.
    def suppressed
      @suppress = true
      yield
    ensure
      @suppress = false
    end

    def escape(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # Collapse each http(s) word to a shortened, clickable "(link)". Non-URL
    # words are escaped as visible text; URLs are escaped for use inside the
    # href attribute. Gtk::Label's default activate-link handler opens the URL
    # in the browser.
    def linkify(text)
      text.split.map do |word|
        if Links.url?(word)
          "(<a href=\"#{escape(word).gsub("\"", "&quot;")}\">link</a>)"
        else
          escape(word)
        end
      end.join(" ")
    end
  end
end
