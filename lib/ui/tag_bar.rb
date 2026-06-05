# frozen_string_literal: true

require "gtk3"

module UI
  # A wrapping row of toggle chips, one per "@tag" found in the lane, shown
  # under the header. Selecting chips filters the checklist view to matching
  # items; each selected tag gets its own heading. The bar hides itself when
  # the lane has no tags, so the default view loses no vertical space.
  #
  # Built as a FlowBox (which wraps chips onto multiple rows) holding
  # independent ToggleButtons, rather than relying on FlowBox's own single-row
  # selection, so each chip toggles on its own and several can be active.
  class TagBar < Gtk::FlowBox
    attr_reader :selected

    def initialize(&on_change)
      super()
      @on_change = on_change
      @selected = Set.new
      self.selection_mode = :none
      self.homogeneous = false
      self.no_show_all = true # stays hidden until a lane actually has tags
      style_context.add_class("tag-bar")
    end

    # Repopulate the chips for `tags` (BoardFetch::Tag values). `selected` is
    # the set of tag names to start pressed (those a refresh carried over that
    # still exist); any other selected name is simply dropped.
    def set_tags(tags, selected)
      children.each { |child| remove(child) }
      @selected = tags.to_set(&:name) & selected

      tags.each { |tag| add_chip(tag) }

      # set_visible, not show_all: the bar's no_show_all makes show_all a no-op.
      set_visible(!tags.empty?)
    end

    private

    def add_chip(tag)
      button = Gtk::ToggleButton.new(label: "#{tag.name} (#{tag.item_count})")
      button.can_focus = false
      button.style_context.add_class("tag-chip")
      # Set the initial pressed state *before* wiring "toggled", so repopulating
      # the bar doesn't fire a spurious change for each carried-over selection.
      button.active = @selected.include?(tag.name)
      button.signal_connect("toggled") { toggle(tag.name, button.active?) }
      insert(button, -1)
      # Each chip needs an explicit show; no_show_all blocks a bulk show_all.
      children.last.show_all
    end

    def toggle(name, active)
      active ? @selected.add(name) : @selected.delete(name)
      @on_change&.call(@selected)
    end
  end
end
