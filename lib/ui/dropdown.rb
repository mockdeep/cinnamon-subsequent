# frozen_string_literal: true

require "gtk3"

module UI
  # A dropdown selector built from a MenuButton + Popover (not a ComboBox).
  # A popover anchors directly below its button and is constrained to the
  # window, so it positions reliably even when the sidebar is flush against the
  # screen edge — unlike combo menus, which fly off-screen there.
  #
  # The button label ellipsizes, so two of these share a narrow row without
  # forcing the window wider.
  class Dropdown < Gtk::MenuButton
    # `popover_position:` is where the list opens relative to the button —
    # :bottom for the header dropdowns, :top for ones sitting at the screen
    # bottom (where a downward popover would have no room).
    def initialize(popover_position: :bottom, &on_change)
      super()
      @popover_position = popover_position
      @on_change = on_change
      @items = []
      @active_id = nil
      @row_ids = {}
      self.can_focus = false
      style_context.add_class("dropdown")

      build_face
      build_popover
    end

    def set_items(items, active_id)
      @items = items || []
      rebuild
      self.active_id = active_id
    end

    def active_id=(id)
      @active_id = id
      item = @items.find { |i| i["id"] == id }
      @label.text = item ? item["name"] : ""
    end

    def active_id = @active_id

    private

    def build_face
      remove(child) # drop MenuButton's default arrow image (always present)

      face = Gtk::Box.new(:horizontal, 4)
      @label = Gtk::Label.new("")
      @label.ellipsize = :end
      @label.xalign = 0
      caret = Gtk::Label.new("▾")
      caret.style_context.add_class("caret")
      face.pack_start(@label, expand: true, fill: true, padding: 0)
      face.pack_end(caret, expand: false, fill: false, padding: 0)
      add(face)
      face.show_all
    end

    def build_popover
      @popover = Gtk::Popover.new(self)
      self.popover = @popover
      # After popover=, not before: MenuButton#popover= re-derives the position
      # from the button's arrow direction, clobbering an earlier assignment.
      @popover.position = @popover_position

      scroller = Gtk::ScrolledWindow.new
      scroller.set_policy(:never, :automatic)
      scroller.propagate_natural_height = true
      scroller.max_content_height = 400

      @listbox = Gtk::ListBox.new
      @listbox.style_context.add_class("dropdown-list")
      @listbox.signal_connect("row-activated") { |_listbox, row| choose(row) }

      scroller.add(@listbox)
      @popover.add(scroller)
      scroller.show_all
    end

    def rebuild
      @listbox.children.each { |row| @listbox.remove(row) }
      @row_ids.clear

      @items.each do |item|
        row = Gtk::ListBoxRow.new
        label = Gtk::Label.new(item["name"])
        label.xalign = 0
        label.margin_top = 4
        label.margin_bottom = 4
        label.margin_start = 8
        label.margin_end = 8
        row.add(label)
        @row_ids[row] = item["id"]
        @listbox.add(row)
      end
      @listbox.show_all
    end

    def choose(row)
      @popover.popdown
      id = @row_ids[row]
      return if id.nil? || id == @active_id

      self.active_id = id
      @on_change&.call(id)
    end
  end
end
