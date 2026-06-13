# frozen_string_literal: true

require "gtk3"
require "x11/strut"
require "ui/checklist_view"
require "ui/tag_bar"
require "ui/limit_bar"
require "ui/session_bar"

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

    private

    # Position, size, and strut for the current @dock_width (expanded or
    # collapsed). Re-run whenever the width changes.
    def relayout
      monitor, workarea, screen_width = geometry
      layout = self.class.layout_for(
        monitor: monitor,
        workarea: workarea,
        screen_width: screen_width,
        dock_width: @dock_width,
        scale: window.scale_factor,
      )
      move(layout.x, layout.y)
      set_size_request(layout.width, layout.height)
      resize(layout.width, layout.height)
      X11::Strut.apply_right(window.xid,
                             width: layout.strut_width,
                             start_y: layout.strut_start_y,
                             end_y: layout.strut_end_y)
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
      @tag_bar = TagBar.new { |selected| @on_tag_change&.call(selected) }
      expanded.pack_start(@tag_bar, expand: false, fill: false, padding: 0)
      @checklist_view = ChecklistView.new
      expanded.pack_start(@checklist_view, expand: true, fill: true, padding: 0)
      @limit_bar = LimitBar.new { |limit| @on_limit_change&.call(limit) }
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

    def apply_css
      css = <<~CSS
        .dock-window { background-color: #181c25; }
        .sidebar  { background-color: #1f2430; color: #e6e6e6; font-size: 13px; }
        .topbar   { background-color: #181c25; border-bottom: 1px solid #3a4150; }
        .checklist-header { color: #8fb3ff; font-size: 11px; font-weight: bold; margin-top: 6px; margin-bottom: 2px; }
        .open-links {
          background-image: none;
          background-color: #2a3140;
          color: #cdd6e6;
          border: 1px solid #3a4150;
          box-shadow: none;
          text-shadow: none;
          border-radius: 6px;
          padding: 0 8px;
          min-height: 0;
          min-width: 0;
          font-size: 11px;
        }
        .open-links:hover { background-color: #333b4d; }
        .item-row { padding: 2px 0; }
        .item-row.done label { color: #6f7787; }
        .item-row.failed label { color: #ff8a8a; }
        .empty-state { color: #9aa3b2; font-style: italic; }
        .loading { color: #9aa3b2; }
        .more-hint { color: #6f7787; font-size: 11px; font-style: italic; }

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

        /* Tag bar: wrapping row of toggle chips under the header. The flowbox
           and its child wrappers stay transparent (selection_mode is :none, so
           the chips carry all the visible state). */
        .tag-bar { background-color: #181c25; border-bottom: 1px solid #3a4150; padding: 4px 6px; }
        .tag-bar, .tag-bar flowboxchild { background-color: transparent; border: none; padding: 0; min-width: 0; min-height: 0; }
        .tag-bar flowboxchild:selected { background-color: transparent; }
        .tag-chip {
          background-image: none;
          background-color: #2a3140;
          color: #cdd6e6;
          border: 1px solid #3a4150;
          box-shadow: none;
          text-shadow: none;
          border-radius: 10px;
          padding: 0 8px;
          margin: 2px;
          min-height: 0;
          font-size: 11px;
        }
        .tag-chip:hover { background-color: #333b4d; }
        .tag-chip:checked { background-color: #34507e; color: #ffffff; border-color: #4a6aa5; }

        /* Limit bar: slim strip along the window bottom holding the
           items-per-list dropdown. */
        .limit-bar { background-color: #181c25; border-top: 1px solid #3a4150; padding: 4px 8px; font-size: 11px; }
        /* Child combinator: dims only the bar's own caption, not the label
           nested inside the dropdown's face. */
        .limit-bar > label { color: #9aa3b2; }
        .limit-bar .dropdown {
          background-image: none;
          background-color: #2a3140;
          color: #e6e6e6;
          border: 1px solid #3a4150;
          box-shadow: none;
          text-shadow: none;
          padding: 0 6px;
          min-height: 0;
          min-width: 0;
        }
        .limit-bar .dropdown:hover { background-color: #333b4d; }
        .limit-bar .dropdown .caret { color: #9aa3b2; }

        /* Session dots footer: a wrapping row of Claude-session dots pinned to
           the window bottom. The flowbox and its child wrappers stay
           transparent — the dots are cairo-drawn and carry all the colour. */
        .session-bar { background-color: #181c25; border-top: 1px solid #3a4150; padding: 8px 6px; }

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
