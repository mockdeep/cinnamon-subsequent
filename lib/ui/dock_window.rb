# frozen_string_literal: true

require "gtk3"
require "x11/strut"
require "ui/checklist_view"

module UI
  # A borderless, full-height window pinned to a screen edge that reserves its
  # space via a strut, so maximized windows stop at it. Sticky across all
  # workspaces, kept below normal windows, and never in the taskbar/alt-tab.
  class DockWindow < Gtk::Window
    def initialize(edge: :right, width: 320, header:)
      super(:toplevel)
      @edge = edge
      @dock_width = width
      @header = header

      self.title = "cinnamon-subsequent"
      self.type_hint = :dock
      self.decorated = false
      self.skip_taskbar_hint = true
      self.skip_pager_hint = true
      self.accept_focus = false
      self.focus_on_map = false
      self.resizable = false

      build_content
      signal_connect("destroy") { Gtk.main_quit }
    end

    # Called when a row is clicked: block receives (row, item, desired_state).
    def on_item_toggle(&block)
      @on_item_toggle = block
    end

    # Replace the displayed checklists with a freshly fetched view model.
    def render(result)
      @checklist_view.render(result, on_toggle: @on_item_toggle)
    end

    # Show a spinner in the content area while a fetch is in flight.
    def render_loading
      @checklist_view.render_loading
    end

    # Position, size, strut, stick, keep-below — done after the window is
    # realized so it has an XID and the WM has mapped it.
    def apply_dock_behaviour
      geo, wa, screen_w = geometry
      x = geo.x + geo.width - @dock_width

      move(x, wa.y)
      set_size_request(@dock_width, wa.height)
      resize(@dock_width, wa.height)

      set_keep_below(true)
      stick

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

    private

    def geometry
      display = Gdk::Display.default
      monitor = display.primary_monitor || display.get_monitor(0)
      [monitor.geometry, monitor.workarea, Gdk::Screen.default.width]
    end

    def build_content
      apply_css

      root = Gtk::Box.new(:vertical, 0)
      root.style_context.add_class("sidebar")

      root.pack_start(@header, expand: false, fill: false, padding: 0)

      @checklist_view = ChecklistView.new
      root.pack_start(@checklist_view, expand: true, fill: true, padding: 0)

      add(root)
    end

    def apply_css
      css = <<~CSS
        .sidebar  { background-color: #1f2430; color: #e6e6e6; font-size: 13px; }
        .topbar   { background-color: #181c25; border-bottom: 1px solid #3a4150; }
        .checklist-header { color: #8fb3ff; font-size: 11px; font-weight: bold; margin-top: 6px; margin-bottom: 2px; }
        .item-row { padding: 2px 0; }
        .item-row.done label { color: #6f7787; }
        .item-row.failed label { color: #ff8a8a; }
        .empty-state { color: #9aa3b2; font-style: italic; }
        .loading { color: #9aa3b2; }
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
