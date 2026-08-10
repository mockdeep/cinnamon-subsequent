# frozen_string_literal: true

module UI
  # The sidebar's stylesheet, as one string for a Gtk::CssProvider.
  #
  # Everything scales off a single base font size: body text sits at `base`,
  # the secondary text (checklist headers, chips, hints, the footer) two px
  # under it, and the icon glyphs a few over — so stepping the size with the
  # footer's A-/A+ buttons keeps the proportions intact.
  module Styles
    module_function

    # The whole sheet at `base` px body text.
    def sheet(base)
      [content(base), controls(base), footer(base), collapsed(base)].join("\n")
    end

    # The window, the list of checklists, and the scrollbar beside them.
    def content(base)
      small = base - 2
      <<~CSS
        .dock-window { background-color: #181c25; }
        .sidebar  { background-color: #1f2430; color: #e6e6e6; font-size: #{base}px; }
        .topbar   { background-color: #181c25; border-bottom: 1px solid #3a4150; }
        .checklist-header { color: #8fb3ff; font-size: #{small}px; font-weight: bold; margin-top: 6px; margin-bottom: 2px; }
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
          font-size: #{small}px;
        }
        .open-links:hover { background-color: #333b4d; }
        .item-row { padding: 2px 0; }
        .item-row.done label { color: #6f7787; }
        .item-row.failed label { color: #ff8a8a; }
        .empty-state { color: #9aa3b2; font-style: italic; }
        .loading { color: #9aa3b2; }
        .more-hint { color: #6f7787; font-size: #{small}px; font-style: italic; }

        /* Dark scrollbar. Paint trough/scrolledwindow explicitly dark (NOT
           transparent — transparent reveals the light theme base behind the
           scrollbar as a white strip on the edge). */
        scrolledwindow, scrolledwindow > viewport { background-color: #1f2430; border: none; }
        scrollbar, scrollbar trough { background-color: #1f2430; border: none; }
        scrollbar slider { background-color: #3a4150; border: 2px solid #1f2430; border-radius: 6px; min-width: 7px; }
        scrollbar slider:hover { background-color: #4a5468; }
      CSS
    end

    # Topbar buttons and dropdowns, plus the tag chips under them.
    def controls(base)
      <<~CSS
        .refresh, .collapse { padding: 2px 6px; font-size: #{base + 2}px; min-width: 0; }

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
          font-size: #{base - 2}px;
        }
        .tag-chip:hover { background-color: #333b4d; }
        .tag-chip:checked { background-color: #34507e; color: #ffffff; border-color: #4a6aa5; }
      CSS
    end

    # The limit bar (cap dropdown + text-size steppers) and the session dots
    # below it, both pinned to the window bottom.
    def footer(base)
      <<~CSS
        /* Limit bar: slim strip along the window bottom holding the
           items-per-list dropdown and the text-size steppers. */
        .limit-bar { background-color: #181c25; border-top: 1px solid #3a4150; padding: 4px 8px; font-size: #{base - 2}px; }
        /* Child combinator: dims only the bar's own caption, not the label
           nested inside the dropdown's face. */
        .limit-bar > label { color: #9aa3b2; }
        .limit-bar .dropdown,
        .limit-bar .font-step {
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
        .limit-bar .dropdown:hover,
        .limit-bar .font-step:hover { background-color: #333b4d; }
        .limit-bar .dropdown .caret { color: #9aa3b2; }
        /* A stepper sitting on its size limit: visibly there, visibly spent. */
        .limit-bar .font-step:disabled { color: #5a616f; background-color: #232936; }

        /* Session dots footer: a wrapping row of Claude-session dots pinned to
           the window bottom. The flowbox and its child wrappers stay
           transparent — the dots are cairo-drawn and carry all the colour. */
        .session-bar { background-color: #181c25; border-top: 1px solid #3a4150; padding: 8px 6px; }
      CSS
    end

    # The collapsed strip, and the popovers that open over either state.
    def collapsed(base)
      <<~CSS
        .strip { background-color: #181c25; background-image: none; border: none; border-radius: 0; box-shadow: none; padding: 0; outline: none; }
        .strip:hover { background-color: #232a36; }
        .strip .chevron { color: #8fb3ff; font-size: #{base + 3}px; }
        .strip .strip-count { color: #e6e6e6; font-size: #{base - 1}px; }

        /* Popover dropdown list */
        popover { background-color: #232a36; padding: 2px; }
        .dropdown-list { background-color: transparent; }
        .dropdown-list row { color: #e6e6e6; }
        .dropdown-list row:hover { background-color: #2f3848; }
        .dropdown-list row:selected { background-color: #34507e; color: #ffffff; }
        checkbutton check { min-width: 14px; min-height: 14px; }
      CSS
    end
  end
end
