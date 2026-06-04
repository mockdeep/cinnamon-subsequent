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

Build deps: the `gtk3` gem builds native extensions and needs **`libgtk-3-dev`**
(`sudo apt install libgtk-3-dev`); the rest of the chain is already present.
Ruby is mise-managed — always run via `bundle exec`.

```
bundle exec ruby bin/todo-sidebar          # run it
DISPLAY=:0 timeout 6 bundle exec ruby bin/todo-sidebar   # smoke test: exit 124 = booted clean
```

For visual checks, launch with `nohup … &`, inspect, then kill. Useful tools:

- `xwininfo -name cinnamon-subsequent` — window geometry.
- **Screenshot + pixel-sample** to diagnose rendering (how the right-edge line
  was found): `import -window root -crop WxH+X+Y out.png`, then
  `convert out.png -format '%[pixel:p{0,0}]' info:-`.
- **Killing instances:** do NOT `pkill -f bin/todo-sidebar` — that pattern
  matches your own shell command line and kills the command itself. Instead
  iterate `pgrep -x ruby` and check `/proc/$pid/cmdline`, or use a saved PID.

There is no automated test suite; verification is the smoke test plus visual
inspection.

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
- **The window is permanently in CSS `:backdrop` state** — it never takes focus
  (`accept_focus = false`). When writing CSS, remember normal/`:hover` states may
  behave unexpectedly; the widget path shows `window:backdrop`.
- **Dropdowns are Popovers, not ComboBoxes** (`lib/ui/dropdown.rb`). Combo menus
  fly off-screen to the left when the window is flush against the right edge, and
  their minimum width forced the window wider than 320px. Do **not** "simplify"
  back to `Gtk::ComboBoxText`.
- **`DockWindow::EDGE_BLEED` is load-bearing — don't "simplify" it away.** The
  GTK theme paints a ~1px light line on the window's right edge that NO CSS
  removes (it's not a border/shadow/scrollbar/background — verified by walking
  the widget tree and pixel-sampling). The window is rendered a few px wider than
  its visible width so that column is clipped off the screen edge; the strut
  still reserves the true width. Trade-off: on scrolling lanes a few px of the
  scrollbar sit off-screen (wheel/trackpad scrolling is unaffected).
- **Collapse/expand** (the `»` button → thin strip via a `Gtk::Stack`) is an
  instant width swap. Animating the window width was tried and **abandoned as
  janky** — GTK window-resize tweens stutter; don't reattempt.
- **`Gtk::Label` link markup ≠ Pango markup.** Item labels render URLs as a
  clickable `(<a href="…">link</a>)` (`ItemRow#linkify`). The `<a>` tag is a
  *GTK* extension — `Pango.parse_markup` rejects it (`Unknown tag 'a'`), so
  validate label markup by setting it on a real `Gtk::Label`, not via Pango.
  This binding also has no `GLib::Markup`, so href escaping is hand-rolled.
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
