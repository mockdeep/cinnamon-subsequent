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

### Automated tests

```
bundle exec rspec               # the spec suite (needs a display — see below)
bundle exec rake                # spec + rubocop (the default task)
xvfb-run -a bundle exec rake    # headless (what CI runs)
```

RSpec covers **all of `lib/`** at 100% line + branch coverage (SimpleCov reports
it; there is **no** coverage gate):

- `config.rb`, `trello_client.rb`, `board_fetch.rb` — pure, no GTK. Trello calls
  are stubbed with WebMock (no real network in specs).
- `sync.rb` — drives a real `GLib::MainLoop` headlessly (GLib needs no display).
- `app.rb` — the orchestration cascade. Only the UI boundary is doubled
  (`header:`/`window:` — `App.new` takes these keyword args for exactly this);
  `Config`, `TrelloClient` (over WebMock), and `BoardFetch` run for real, and
  `Sync.run` is stubbed to run inline.
- `lib/ui/*` — real widgets under a display. Tests assert on the **public widget
  tree** (`row.children.grep(Gtk::Label)`, `dropdown.popover.child.child.child`)
  and getters (`style_context.has_class?`, `visible?`, `label.label`). User
  actions are simulated by driving the widgets (`checkbox.active = true`,
  `listbox.signal_emit("row-activated", row)`, `button.clicked`). Some specs need
  `widget.show_all` first or visibility/stack-switching won't read back.
- `lib/x11/strut.rb` — the Xlib FFI `Lib` module is stubbed (`stub_const`), so
  the spec asserts the strut **arrays/atoms** without a real X server.
- `dock_window.rb` — `collapse`/`expand`/`apply_dock_behaviour` run for real
  under xvfb (real `relayout`, including the Xlib strut), so nothing is stubbed
  there. The HiDPI scale math is extracted into the pure `DockWindow.layout_for`
  and tested in isolation at `scale: 2` (xvfb only ever reports scale 1). Note
  `strut_spec` resets `X11::Strut`'s memoized `@display` in an `after`, so its
  stubbed display can't leak into these real Xlib calls.

**The full suite needs a display.** Requiring any `ui/*` file (or `app`, which
pulls them in) *defines* a `Gtk::*` subclass, which calls `Gtk.init` and fails
with no display. So locally you rely on your X server; CI wraps `rake` in
`xvfb-run`. Only `config`/`trello`/`board_fetch`/`sync`/`strut` specs are
display-free, so those files can be run individually headless.

RuboCop uses a strict `EnabledByDefault: true` config; pre-existing offenses are
shelved in `.rubocop_todo.yml`, so a clean run means "no *new* offenses," not
"nothing to clean up."

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
  potentially stale list. Offline isn't handled by caching but by **refresh
  recovery** (see "The Trello model" below): a start with no network leaves empty
  dropdowns that a single Refresh repopulates once the connection is back.

## The Trello model, briefly

`selected lane → first card → its checklists → incomplete items only`, grouped by
checklist. Completing/uncompleting an item is `PUT /cards/{id}/checkItem/{id}`
with `state=complete|incomplete`, pushed immediately on click (spinner while in
flight; completed rows stay visible and undoable until the next refresh, which
refetches incomplete-only).

**Refresh re-enters the cascade at the top** (`App#refresh_view` → `load_boards`),
not at the leaf card fetch — so the Board/Lane dropdowns repopulate, not just the
checklist. This is deliberate: it's the recovery path for a cold start that failed
with **no network** (boards/lanes never loaded), where a leaf-only refresh would
leave the dropdowns permanently empty even after reconnecting. The persisted
`board_id`/`lane_id` keep the current selection across the reload. Cost: every
refresh is the full 3-call cascade, not one card fetch.

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
