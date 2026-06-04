# frozen_string_literal: true

require "gtk3"
require "ui/item_row"

module UI
  # Scrolling column that renders a BoardFetch::Result: a header per checklist
  # followed by its incomplete item rows, or a single empty-state message.
  # Horizontal scrolling is disabled so long item labels wrap instead of
  # widening the sidebar.
  class ChecklistView < Gtk::ScrolledWindow
    def initialize
      super()
      set_policy(:never, :automatic)

      @list = Gtk::Box.new(:vertical, 2)
      @list.margin = 12
      add(@list) # ScrolledWindow wraps a plain box in a viewport automatically
    end

    def render(result, on_toggle: nil)
      @list.children.each { |child| @list.remove(child) }

      if result.groups.empty?
        @list.pack_start(empty_label(result.empty_reason), expand: false, fill: false, padding: 8)
      else
        result.groups.each { |group| append_group(group, on_toggle) }
      end

      @list.show_all
    end

    # A spinner + "Loading…" shown while a fetch runs (startup, board/lane switch).
    def render_loading
      @list.children.each { |child| @list.remove(child) }

      row = Gtk::Box.new(:horizontal, 8)
      row.style_context.add_class("loading")
      spinner = Gtk::Spinner.new
      spinner.start
      row.pack_start(spinner, expand: false, fill: false, padding: 0)
      row.pack_start(Gtk::Label.new("Loading…"), expand: false, fill: false, padding: 0)

      @list.pack_start(row, expand: false, fill: false, padding: 8)
      @list.show_all
    end

    private

    def append_group(group, on_toggle)
      @list.pack_start(header(group.name), expand: false, fill: false, padding: 0)
      group.items.each do |item|
        @list.pack_start(ItemRow.new(item, on_toggle: on_toggle), expand: false, fill: false, padding: 0)
      end
      @list.pack_start(spacer, expand: false, fill: false, padding: 4)
    end

    def header(name)
      label = Gtk::Label.new(name)
      label.xalign = 0
      label.wrap = true
      label.style_context.add_class("checklist-header")
      label
    end

    def empty_label(reason)
      label = Gtk::Label.new(reason || "Nothing here.")
      label.xalign = 0
      label.wrap = true
      label.style_context.add_class("empty-state")
      label
    end

    def spacer
      box = Gtk::Box.new(:vertical, 0)
      box.style_context.add_class("group-spacer")
      box
    end
  end
end
