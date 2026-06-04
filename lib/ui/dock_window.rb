# frozen_string_literal: true

require "gtk3"
require "x11/strut"
require "ui/checklist_view"

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

    def initialize(edge: :right, width: 320, header:)
      super(:toplevel)
      @edge = edge
      @expanded_width = width
      @dock_width = width
      @collapsed = false
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
      @header.on_collapse { collapse }
      signal_connect("destroy") { Gtk.main_quit }
    end

    # Called when a row is clicked: block receives (row, item, desired_state).
    def on_item_toggle(&block)
      @on_item_toggle = block
    end

    # Replace the displayed checklists with a freshly fetched view model.
    def render(result)
      @checklist_view.render(result, on_toggle: @on_item_toggle)
      total = result.groups.sum { |group| group.items.size }
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

    private

    # Position, size, and strut for the current @dock_width (expanded or
    # collapsed). Re-run whenever the width changes.
    def relayout
      geo, wa, screen_w = geometry
      x = geo.x + geo.width - @dock_width

      # Render a few px wider so the theme's light right-edge column is clipped
      # off-screen; the visible width is still @dock_width.
      rendered = @dock_width + EDGE_BLEED
      move(x, wa.y)
      set_size_request(rendered, wa.height)
      resize(rendered, wa.height)

      # GTK lays out in logical pixels; X11 struts are in device pixels.
      # On a HiDPI display (scale_factor > 1) we must convert, or we'd reserve
      # too little and maximized windows would overlap the dock.
      scale = window.scale_factor
      right = (screen_w - (geo.x + geo.width) + @dock_width) * scale
      X11::Strut.apply_right(window.xid,
                             width: right,
                             start_y: wa.y * scale,
                             end_y: (wa.y + wa.height) * scale - 1)
    end

    def geometry
      display = Gdk::Display.default
      monitor = display.primary_monitor || display.get_monitor(0)
      [monitor.geometry, monitor.workarea, Gdk::Screen.default.width]
    end

    def build_content
      apply_css

      expanded = Gtk::Box.new(:vertical, 0)
      expanded.style_context.add_class("sidebar")
      expanded.pack_start(@header, expand: false, fill: false, padding: 0)
      @checklist_view = ChecklistView.new
      expanded.pack_start(@checklist_view, expand: true, fill: true, padding: 0)

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

      button.add(box)
      button.signal_connect("clicked") { expand }
      button
    end

    def apply_css
      css = <<~CSS
        .dock-window { background-color: #181c25; }
        .sidebar  { background-color: #1f2430; color: #e6e6e6; font-size: 13px; }
        .topbar   { background-color: #181c25; border-bottom: 1px solid #3a4150; }
        .checklist-header { color: #8fb3ff; font-size: 11px; font-weight: bold; margin-top: 6px; margin-bottom: 2px; }
        .item-row { padding: 2px 0; }
        .item-row.done label { color: #6f7787; }
        .item-row.failed label { color: #ff8a8a; }
        .empty-state { color: #9aa3b2; font-style: italic; }
        .loading { color: #9aa3b2; }

        /* Dark scrollbar. Paint trough/scrolledwindow explicitly dark (NOT
           transparent — transparent reveals the light theme base behind the
           scrollbar as a white strip on the edge). */
        scrolledwindow, scrolledwindow > viewport { background-color: #1f2430; border: none; }
        scrollbar, scrollbar trough { background-color: #1f2430; border: none; }
        scrollbar slider { background-color: #3a4150; border: 2px solid #1f2430; border-radius: 6px; min-width: 7px; }
        scrollbar slider:hover { background-color: #4a5468; }
        .refresh, .collapse { padding: 2px 6px; font-size: 15px; min-width: 0; }

        /* Flat, dark controls that blend into the sidebar. */
        .topbar .dropdown,
        .topbar button.refresh,
        .topbar button.collapse {
          background-image: none;
          background-color: #2a3140;
          color: #e6e6e6;
          border: 1px solid #3a4150;
          box-shadow: none;
          text-shadow: none;
          padding: 2px 6px;
        }
        .topbar .dropdown:hover,
        .topbar button.refresh:hover,
        .topbar button.collapse:hover { background-color: #333b4d; }
        .topbar .dropdown .caret { color: #9aa3b2; }

        /* Collapsed strip */
        .strip { background-color: #181c25; background-image: none; border: none; border-radius: 0; box-shadow: none; padding: 0; outline: none; }
        .strip:hover { background-color: #232a36; }
        .strip .chevron { color: #8fb3ff; font-size: 16px; }
        .strip .strip-count { color: #e6e6e6; font-size: 12px; }

        /* Popover dropdown list */
        popover { background-color: #232a36; padding: 2px; }
        .dropdown-list { background-color: transparent; }
        .dropdown-list row { color: #e6e6e6; }
        .dropdown-list row:hover { background-color: #2f3848; }
        .dropdown-list row:selected { background-color: #34507e; color: #ffffff; }
        checkbutton check { min-width: 14px; min-height: 14px; }
      CSS
      provider = Gtk::CssProvider.new
      provider.load(data: css)
      Gtk::StyleContext.add_provider_for_screen(
        Gdk::Screen.default, provider, Gtk::StyleProvider::PRIORITY_APPLICATION
      )
    end
  end
end
