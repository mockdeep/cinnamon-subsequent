# AGENTS.md

Guidance for AI agents (and humans) working on this repo. Focuses on what is
**not** obvious from reading the code — the gotchas and the "why"s.

## What this is

A persistent Trello to-do **sidebar** for Linux Mint / Cinnamon: a borderless
GTK3 window pinned to the right screen edge that reserves its space (maximized
windows stop at it), shows on all workspaces, never takes focus, and renders the
checklists of the first card in a chosen board+lane. Click an item to complete
it (pushed to Trello immediately). Single process, Ruby + GTK3.

## Running & verifying

It's a GUI app on **X11** (`DISPLAY=:0`), so you can launch it and see it on
screen — prefer that over guessing.

```
bundle exec ruby bin/todo-sidebar          # run it
DISPLAY=:0 timeout 6 bundle exec ruby bin/todo-sidebar   # smoke test: exit 124 = booted clean
```

For visual checks, launch it with `nohup … &`, inspect, then kill it. Window
geometry is checkable with `xwininfo -name cinnamon-subsequent`.

## Hard constraints & gotchas

- **X11 + GTK3 only.** Not GTK4 — it removed the window-manager hint APIs
  (`set_type_hint`, `set_keep_below`, `set_skip_taskbar_hint`, `stick`) a dock
  needs. Not Wayland — Cinnamon/Muffin is X11.
- **HiDPI struts.** `_NET_WM_STRUT_PARTIAL` is in **device** pixels; GTK lays out
  in **logical** pixels. Multiply strut width / y-bounds by
  `window.scale_factor` (see `DockWindow#apply_dock_behaviour`) or a 2× display
  reserves half the dock width.
- **Strut via `fiddle`→Xlib** (`lib/x11/strut.rb`). gdk3 doesn't expose
  `gdk_property_change`. The XID comes from `widget.window.xid` (`#id` does not
  work).
- **Threading.** Network runs on a worker thread via `Sync.run`; results return
  to the UI **only** through `GLib::Idle.add`. Never touch widgets off the main
  thread.
- **Dropdowns are Popovers, not ComboBoxes** (`lib/ui/dropdown.rb`). Combo menus
  fly off-screen to the left when the window is flush against the right edge, and
  their minimum width forced the window wider than 320px. Do **not** "simplify"
  back to `Gtk::ComboBoxText`.
- **Gems are global (mise gemset), not vendored.** Never run
  `bundle config path vendor/bundle` — this project lives in Dropbox and 80MB of
  compiled native extensions should not sync.
- **Autostart uses the resolved ruby install path, not the mise shim.** The shim
  (`~/.local/share/mise/shims/ruby`) errors "No version is set for shim" in a
  login session with no global mise version. `scripts/install-autostart.sh`
  bakes `mise which ruby` (an absolute install path) into the `.desktop` Exec.

## Where things live

- **Trello credentials + selected board/lane:** `~/.config/cinnamon-subsequent/config.json`
  (`0600`). Never in the repo.
- No on-disk task cache: a deliberate choice — show a fresh loader rather than a
  potentially stale list (offline isn't a concern here).

## The Trello model, briefly

`selected lane → first card → its checklists → incomplete items only`, grouped by
checklist. Completing/uncompleting an item is `PUT /cards/{id}/checkItem/{id}`
with `state=complete|incomplete`, pushed immediately on click (spinner while in
flight; completed rows stay visible and undoable until the next refresh, which
refetches incomplete-only).

## Architecture map

- `bin/todo-sidebar` — entry point.
- `lib/app.rb` — orchestrator: drives the board → lane → fetch cascade, all async.
- `lib/config.rb` — config file load/save.
- `lib/trello_client.rb` — Trello REST (stdlib net/http).
- `lib/board_fetch.rb` — builds the view model (the structs the UI renders).
- `lib/sync.rb` — worker-thread + main-thread marshalling helper.
- `lib/x11/strut.rb` — the Xlib strut call.
- `lib/ui/` — `dock_window` (window + strut + CSS), `header`, `dropdown`,
  `checklist_view`, `item_row`.
