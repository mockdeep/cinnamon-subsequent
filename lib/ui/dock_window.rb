# frozen_string_literal: true

require "gtk3"
require "x11/strut"
require "ui/checklist_view"
require "ui/tag_bar"
require "ui/limit_bar"
require "ui/session_bar"
require "ui/styles"

module UI
  # A borderless, full-height window pinned to a screen edge that reserves its
  # space via a strut, so maximized windows stop at it. Sticky across all
  # workspaces, kept below normal windows, and never in the taskbar/alt-tab.
  class DockWindow < Gtk::Window
    COLLAPSED_WIDTH = 28

    # The theme paints a ~1px light edge on the window's right that no CSS
    # reliably removes. Bleed the window a few px past the right screen edge so
    # that column is clipped off-screen; content still fills to the visible edge.
    EDGE_BLEED = 3

    # Window placement (logical px) plus the reserved strut (device px).
    Layout = Struct.new(:x,
                        :y,
                        :width,
                        :height,
                        :strut_width,
                        :strut_start_y,
                        :strut_end_y,
                        keyword_init: true)

    # GTK lays out in logical px but X11 struts are device px, so the strut
    # values are scaled by the display `scale`: on a HiDPI screen (scale > 1)
    # we'd otherwise reserve too little and maximized windows would overlap.
    def self.layout_for(monitor:, workarea:, screen_width:, dock_width:, scale:)
      right_edge = monitor.x + monitor.width
      Layout.new(
        x: right_edge - dock_width,
        y: workarea.y,
        width: dock_width + EDGE_BLEED,
        height: workarea.height,
        strut_width: (screen_width - right_edge + dock_width) * scale,
        strut_start_y: workarea.y * scale,
        strut_end_y: (workarea.y + workarea.height) * scale - 1,
      )
    end

    # `geometry:` is an optional callable returning [monitor, workarea,
    # screen_width]; it defaults to reading GDK. Injectable so specs can move the
    # workarea under the dock without a real panel.
    def initialize(
      edge: :right,
      width: 320,
      font_size: LimitBar::DEFAULT_FONT_SIZE,
      header:,
      geometry: nil
    )
      super(:toplevel)
      @edge = edge
      @geometry = geometry
      @expanded_width = width
      @dock_width = width
      @font_size = font_size
      @collapsed = false
      @last_layout = nil
      @header = header

      self.title = "cinnamon-subsequent"
      style_context.add_class("dock-window")
      self.type_hint = :dock
      self.decorated = false
      self.skip_taskbar_hint = true
      self.skip_pager_hint = true
      self.accept_focus = false
      self.focus_on_map = false
      self.resizable = false

      build_content
      @session_bar =
        SessionBar.new(footer: @session_box, strip: @strip_dots) do |session_id|
          @on_session_focus&.call(session_id)
        end
      @header.on_collapse { collapse }
      signal_connect("destroy") { Gtk.main_quit }
    end

    # Called when a row is clicked: block receives (row, item, desired_state).
    def on_item_toggle(&block)
      @on_item_toggle = block
    end

    # Called when the tag selection changes: block receives the selected Set.
    def on_tag_change(&block)
      @on_tag_change = block
    end

    # Called when the per-list cap changes: block receives an Integer or nil.
    def on_limit_change(&block)
      @on_limit_change = block
    end

    # Called when the dice is toggled, or its count changed while it's on:
    # block receives (random?, count).
    def on_random_change(&block)
      @on_random_change = block
    end

    # Called when the text size changes: block receives the new px size. The
    # window has already restyled itself by then — this is for persisting it.
    def on_font_size_change(&block)
      @on_font_size_change = block
    end

    # Called when a session dot is clicked: block receives the session id.
    def on_session_focus(&block)
      @on_session_focus = block
    end

    # Replace the session dots (footer + strip) from a list of Sessions::Session;
    # focused_xid lights the dot whose terminal window is currently active.
    def set_sessions(sessions, focused_xid)
      @session_bar.render(sessions, focused_xid)
    end

    # Repopulate the tag bar; `selected` is the set of tag names to start pressed.
    def set_tags(tags, selected)
      @tag_bar.set_tags(tags, selected)
    end

    # Reflect a persisted per-list cap in the limit bar (without firing change).
    def item_limit=(limit)
      @limit_bar.limit = limit
    end

    # Reflect a persisted random-pick size in the limit bar (without firing).
    def random_count=(count)
      @limit_bar.random_count = count
    end

    # Restyle the whole sidebar at a new base font size, and keep the footer's
    # steppers in step with it. Doesn't fire on_font_size_change.
    def font_size=(size)
      @font_size = size
      @limit_bar.font_size = size
      apply_css
    end

    attr_reader :font_size

    # Replace the displayed checklists with a freshly fetched view model.
    def render(result)
      @checklist_view.render(result, on_toggle: @on_item_toggle)
      # Count hidden (capped-off) items too: the strip shows what *remains*,
      # not what happens to be rendered.
      total = result.groups.sum { |group| group.items.size + (group.hidden_count || 0) }
      @strip_count.text = total.positive? ? total.to_s : ""
    end

    # Shrink to a thin strip (releases most of the reserved space) / restore.
    def collapse
      return if @collapsed

      @collapsed = true
      @dock_width = COLLAPSED_WIDTH
      @stack.visible_child_name = "collapsed"
      relayout
    end

    def expand
      return unless @collapsed

      @collapsed = false
      @dock_width = @expanded_width
      @stack.visible_child_name = "expanded"
      relayout
    end

    # Show a spinner in the content area while a fetch is in flight.
    def render_loading
      @checklist_view.render_loading
    end

    # Stick / keep-below once, then lay out at the current width. Done after the
    # window is realized so it has an XID and the WM has mapped it.
    def apply_dock_behaviour
      set_keep_below(true)
      stick
      relayout
    end

    # Re-fit the window if the desktop workarea has moved under us: a panel
    # appearing, moving edge, or changing height. Polled from the sidebar's one
    # timer rather than driven by a signal, because GDK doesn't emit one for
    # this — notify::workarea, monitors-changed and size-changed all stay silent
    # on a panel resize, even though GDK's own workarea value updates correctly.
    # So we ask rather than wait to be told, and relayout's guard keeps a tick
    # where nothing moved down to two cached GDK reads and a Struct compare.
    #
    # This is also how a sidebar that started before the panel mapped — the
    # autostart race at login — heals itself instead of sitting underneath it
    # with its bottom strip (the session dots) hidden.
    def check_layout = relayout

    private

    # A stepper click: restyle immediately, then report the size upward so it
    # can be persisted.
    def step_font_size(size)
      self.font_size = size
      @on_font_size_change&.call(size)
    end

    # Position, size, and strut for the current @dock_width (expanded or
    # collapsed). Re-run whenever the width changes, and polled by check_layout
    # for the changes that come from outside.
    #
    # Applying is skipped when the computed layout matches what's already on
    # screen. That's what makes the poll cheap enough to run every tick, and it
    # also stops our own strut write — which itself edits _NET_WORKAREA — from
    # feeding back into the next tick as a fresh change.
    def relayout
      return unless window # not realized yet; apply_dock_behaviour follows

      layout = current_layout
      return if layout == @last_layout

      @last_layout = layout
      apply_layout(layout)
    end

    def current_layout
      monitor, workarea, screen_width = geometry
      self.class.layout_for(
        monitor: monitor,
        workarea: workarea,
        screen_width: screen_width,
        dock_width: @dock_width,
        scale: window.scale_factor,
      )
    end

    def apply_layout(layout)
      move(layout.x, layout.y)
      set_size_request(layout.width, layout.height)
      resize(layout.width, layout.height)
      X11::Strut.apply_right(window.xid,
                             width: layout.strut_width,
                             start_y: layout.strut_start_y,
                             end_y: layout.strut_end_y)
    end

    # GDK hands back the same display, screen and monitors on every poll, and
    # glib2 caches each one's Ruby wrapper on the GObject itself — in qdata
    # that holds no GC reference. Once we drop our last reference the wrapper
    # is collected while that cache goes on pointing at the freed slot, so a
    # later poll is handed an already-freed object and segfaults inside the
    # next introspection call, walking the GC freelist.
    #
    # This is what killed the sidebar every few hours. Reproduced: unpinned
    # dies within ~20k polls, pinned ran 330k+ clean. So we hold on to every
    # GDK object we're handed for the life of the process — a pinned wrapper
    # is exactly what the cache keeps handing back, so it can never go stale.
    #
    # The names are prefixed because Gtk::Widget already defines #display and
    # #screen, which we must not shadow.
    def geometry
      return @geometry.call if @geometry

      monitor = pinned_monitor
      [monitor.geometry, monitor.workarea, pinned_screen.width]
    end

    # Both are fixed for the process's lifetime, so memoising is the whole of
    # the pinning they need.
    def pinned_display = @pinned_display ||= Gdk::Display.default

    def pinned_screen = @pinned_screen ||= Gdk::Screen.default

    # Re-read every poll, because the primary monitor genuinely changes when a
    # monitor is plugged in or the primary is reassigned. Retaining each one we
    # get keeps its wrapper alive across polls that land on a different
    # monitor; the list is bounded by the number of physical monitors.
    def pinned_monitor
      display = pinned_display
      current = display.primary_monitor || display.get_monitor(0)
      @pinned_monitors ||= []
      known = @pinned_monitors.any? { |monitor| monitor.equal?(current) }
      @pinned_monitors << current unless known
      current
    end

    def build_content
      apply_css

      expanded = Gtk::Box.new(:vertical, 0)
      expanded.style_context.add_class("sidebar")
      expanded.pack_start(@header, expand: false, fill: false, padding: 0)
      @tag_bar = TagBar.new { |selected| @on_tag_change&.call(selected) }
      expanded.pack_start(@tag_bar, expand: false, fill: false, padding: 0)
      @checklist_view = ChecklistView.new
      expanded.pack_start(@checklist_view, expand: true, fill: true, padding: 0)
      @limit_bar =
        LimitBar.new(
          font_size: @font_size,
          on_font_change: ->(size) { step_font_size(size) },
          on_random_change: ->(random, count) { @on_random_change&.call(random, count) },
        ) { |limit| @on_limit_change&.call(limit) }
      expanded.pack_start(@limit_bar, expand: false, fill: false, padding: 0)

      # Session dots live at the very bottom — a wrapping row that hides itself
      # when there are no sessions, so it leaves no empty strip behind.
      # A full-width row of session dots, evenly distributed (flexbox
      # space-around): SessionBar packs each dot expand+!fill, so each gets an
      # equal slice of the width and sits centered in it — two dots spread far
      # apart, four pack closer. A Box (not FlowBox) so the row stays single-line.
      @session_box = Gtk::Box.new(:horizontal, 0)
      @session_box.style_context.add_class("session-bar")
      @session_box.no_show_all = true
      expanded.pack_start(@session_box, expand: false, fill: false, padding: 0)

      # Non-homogeneous so the stack requests only the *current* child's width,
      # letting the window actually shrink to the strip.
      @stack = Gtk::Stack.new
      @stack.hhomogeneous = false
      @stack.transition_type = :none
      @stack.add_named(expanded, "expanded")
      @stack.add_named(build_strip, "collapsed")

      add(@stack)
    end

    # The collapsed state: a thin full-height button showing an expand chevron
    # and the count of remaining items. Clicking anywhere on it expands.
    def build_strip
      button = Gtk::Button.new
      button.can_focus = false
      button.style_context.add_class("sidebar")
      button.style_context.add_class("strip")

      box = Gtk::Box.new(:vertical, 6)
      box.margin_top = 10
      chevron = Gtk::Label.new("«")
      chevron.style_context.add_class("chevron")
      @strip_count = Gtk::Label.new("")
      @strip_count.style_context.add_class("strip-count")
      box.pack_start(chevron, expand: false, fill: false, padding: 0)
      box.pack_start(@strip_count, expand: false, fill: false, padding: 0)

      # Display-only session dots stacked under the count. Non-reactive, so a
      # click anywhere on the strip (dots included) still expands it.
      @strip_dots = Gtk::Box.new(:vertical, 6)
      @strip_dots.halign = :center
      @strip_dots.margin_top = 10
      @strip_dots.no_show_all = true
      box.pack_start(@strip_dots, expand: false, fill: false, padding: 0)

      button.add(box)
      button.signal_connect("clicked") { expand }
      button
    end

    # Build (or rebuild) the one app-level style provider. Reloading the same
    # provider restyles every widget live, so a font-size change shows without
    # a restart.
    def apply_css
      @provider ||= new_provider
      @provider.load(data: Styles.sheet(@font_size))
    end

    def new_provider
      provider = Gtk::CssProvider.new
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
      provider
    end
  end
end
