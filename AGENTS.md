# AGENTS.md

Guidance for AI agents (and humans) working on this repo. Focuses on what is
**not** obvious from reading the code — the gotchas and the "why"s.

## What this is

A persistent Trello to-do **sidebar** for Linux Mint / Cinnamon: a borderless
GTK3 window pinned to the right screen edge that reserves its space (maximized
windows stop at it), shows on all workspaces, never takes focus, and renders the
checklists of the first card in a chosen board+lane. Click an item to complete
it (pushed to Trello immediately). A tag bar under the menu filters across all
cards in the lane by `@tag` (parsed from checklist names), and a dice button in
the footer swaps that view for N items drawn at random. Single process,
Ruby + GTK3.

It also folds in a **Claude Code session tracker**: a footer row of colored dots,
one per live `claude` session, that used to be a standalone Cinnamon extension
floating over the bottom-right corner (and blocking clicks there). Moving it into
the sidebar's reserved strut column fixes that — the dots now live in space no
window can cover. See "The session dots" below.

## Running & verifying

It's a GUI app on **X11** (`DISPLAY=:0`), so you can launch it and see it on
screen — prefer that over guessing.

Build deps: the `gtk3` gem builds native extensions and needs **`libgtk-3-dev`**
(`sudo apt install libgtk-3-dev`); the rest of the chain is already present.
Ruby is mise-managed — always run via `bundle exec`.

**Prefer the `rake sidebar:*` tasks** to run and cycle an instance — for a visual
check, `rake sidebar:start`, inspect, then `rake sidebar:stop`:

```
bundle exec rake sidebar:start      # launch detached (survives the shell)
bundle exec rake sidebar:restart    # stop + relaunch with current code
bundle exec rake sidebar:stop       # stop it
bundle exec rake sidebar:status     # running pid, or "not running"
```

The tasks (thin wrappers in the `Rakefile` over the testable
`lib/sidebar_control.rb`) launch via `setsid` (so it outlives the rake process)
and locate the instance via the **pidfile** the app writes on boot
(`lib/pid_file.rb`), so it works for an autostart-launched instance too. The
recorded pid is trusted only after a liveness + identity check (`Process.kill(0,
…)` plus one `/proc/<pid>/cmdline` read confirming it's still our launcher), so a
stale or reused pid reads as "not running" and self-heals.

**There is one launch path.** Both the rake tasks and the login autostart entry
go through `bin/sidebarctl` → `SidebarControl.spawn_detached`, so a
login-started instance gets the same log, environment and already-running guard
as a hand-started one. (It didn't always: autostart used to exec
`bin/todo-sidebar` directly with no redirect, and a crash at login left no
record at all.) `bin/sidebarctl` stays out of Bundler deliberately — it only
touches stdlib, so a half-installed Gemfile can't take autostart down with it.
Anything that needs to happen on every launch belongs in `spawn_detached`, not
in one of the callers.

The log (`/tmp/todo-sidebar.log`) gets a dated `--- sidebar starting … ---` line
per run and rotates to `.log.1` at 1MB. Setting `debug.malloc_check` in
`config.json` relaunches under glibc's allocator checks — see README's *Chasing
a crash*; the `LD_PRELOAD` in `MALLOC_DEBUG_ENV` is load-bearing, not belt-and-
braces, since glibc 2.34 moved malloc_check out of libc proper.

For a one-off boot check without the task machinery, run it in the foreground:

```
DISPLAY=:0 timeout 6 bundle exec ruby bin/todo-sidebar   # exit 124 = booted clean
```

**Caveat:** every launch (incl. this foreground smoke test) writes the pidfile,
so running a bare launch *alongside* a `rake`-managed instance desyncs the file —
`status` can then misreport and `start` can spawn a duplicate. Stick to the rake
tasks for a managed instance; use the foreground run only when none is managed.

Useful tools for visual checks:

- `xwininfo -name cinnamon-subsequent` — window geometry.
- **Screenshot + pixel-sample** to diagnose rendering (how the right-edge line
  was found): `import -window root -crop WxH+X+Y out.png`, then
  `convert out.png -format '%[pixel:p{0,0}]' info:-`.
- **Killing instances:** prefer `rake sidebar:stop` (reads the pidfile). If doing
  it by hand, do NOT `pkill -f bin/todo-sidebar` — that pattern substring-matches
  your own shell command line and kills the command itself. Match the launcher as
  a whole argv element instead: iterate `pgrep -x ruby` and check
  `/proc/$pid/cmdline`, or use a saved PID. (`PidFile.ours?` is the precise
  version: it splits `/proc/<pid>/cmdline` on NUL and checks `end_with?`.)

### Automated tests

```
bundle exec rspec               # the spec suite (needs a display — see below)
bundle exec rake                # spec + rubocop (the default task)
xvfb-run -a bundle exec rake    # headless (what CI runs)
```

RSpec covers nearly all of `lib/` (SimpleCov reports ~96%; there is **no**
coverage gate). The uncovered slivers are the bits that can only be exercised
against a live X server / real process and are verified **on screen** instead:
`X11::ActiveWindow.current` (the Xlib property read — its decode logic *is*
specced via a stubbed `Lib`, but the live `XOpenDisplay` path isn't),
`Sessions::Focus.spawn` (shells out to the hook), and `Watcher#start`'s GLib
timer registration (`#tick` is specced directly):

- `config.rb`, `trello_client.rb`, `board_fetch.rb`, `pid_file.rb`,
  `sidebar_control.rb` — pure, no GTK. Trello calls are stubbed with WebMock (no
  real network in specs); `pid_file` points at a tmpdir via `XDG_RUNTIME_DIR` and
  stubs `/proc` reads; `sidebar_control` stubs `Process`/`PidFile` and captures
  stdout (no process is actually spawned).
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
`xvfb-run`. Only `config`/`trello`/`board_fetch`/`pid_file`/`sidebar_control`/
`sync`/`strut` specs are display-free, so those files can be run individually
headless.

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
- **One CSS provider, reloaded — not a second provider stacked on top.**
  `UI::Styles.sheet(base)` renders the whole sheet from a single base font size
  (secondary text `base − 2`, icons a few px over), and `DockWindow` keeps that
  provider in an ivar so a text-size change just reloads it and every widget
  restyles live. Adding a second provider for "just the font size" would leave
  two sheets fighting at equal priority. Sizes are px, not `em`/`%` — GTK3's CSS
  supports relative font sizes only patchily.
- **The window is permanently in CSS `:backdrop` state** — it never takes focus
  (`accept_focus = false`). When writing CSS, remember normal/`:hover` states may
  behave unexpectedly; the widget path shows `window:backdrop`.
- **`no_show_all` makes `show_all` a no-op on the widget itself.** `UI::TagBar`
  sets `no_show_all = true` so the parent's startup `show_all` doesn't reveal the
  empty bar — but that same flag blocks `show_all` *on the bar*, so chips are
  shown individually (`children.last.show_all` per chip) and the bar is toggled
  with `set_visible`, never `show_all`. The `makes the chips visible, not just
  present` spec pins it (label-only assertions missed it).
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
- **Two timers, deliberately unrelated — don't "unify" them into one poller.**
  `Sessions::Watcher` ticks a 1s `GLib::Timeout` reading the state dir + active
  window; it fires `on_change` only when the visible state changes (id / color /
  status / window / focus), so the pulse animation isn't reset every second.
  `AutoRefresh` ticks every 30s but only *fires* after the sidebar has sat idle
  for `view.refresh_interval_minutes` (default 15). They poll different things at
  different rates for different reasons: one is a local file/X read that must feel
  instant, the other is a network call that must stay rare.
- **Session focus is window-level only.** The old extension tracked Gnome Terminal
  *tab* focus via D-Bus `org.gtk.Actions.Changed` — that needs the Cinnamon shell
  and was dropped in the fold. The focused-dot ring matches on `_NET_ACTIVE_WINDOW`
  (`lib/x11/active_window.rb`, Xlib via fiddle like the strut). Click-to-focus
  still gets tab switching for free: it shells out to the hook's `focus` action.

## Where things live

- **Trello credentials + selected board/lane:** `~/.config/cinnamon-subsequent/config.json`
  (`0600`). Never in the repo. Also holds the UI prefs the sidebar writes as you
  change them — `appearance.font_size` (the `A−`/`A+` steppers),
  `view.item_limit`, and `view.random_count` (how many the dice picks; the dice
  being *on* is not persisted); all fall back to a default if hand-edited to
  nonsense.
  `view.refresh_interval_minutes` is hand-edit-only (nothing in the UI writes it);
  `0` disables auto-refresh. It can't be disabled with `null` — `deep_merge`
  hands an explicit null back to the default — hence 0 as the off switch.
- **Pidfile:** `$XDG_RUNTIME_DIR/cinnamon-subsequent.pid` (falls back to the
  config dir). Written by the app on boot, read by the `sidebar:*` rake tasks
  (`lib/pid_file.rb`). Not authoritative — always liveness/identity-checked.
- No on-disk task cache: a deliberate choice — show a fresh loader rather than a
  potentially stale list. Offline isn't handled by caching but by **refresh
  recovery** (see "The Trello model" below): a start with no network leaves empty
  dropdowns that a single Refresh repopulates once the connection is back — or
  that the next auto-refresh tick repopulates on its own.

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

**Auto-refresh is the quiet inverse of that** (`AutoRefresh` → `App#refresh_quietly`).
It re-enters at the *leaf* — one `cards_with_checklists` call, since the dropdowns
can't have changed while nobody was touching the sidebar — with two deliberate
differences from the button: no `render_loading` over the list (a background
reload shouldn't blank the items or lose scroll position), and a failure that
`warn`s and keeps the current list instead of replacing it with "Trello error:".
The one case it *does* run the loud cascade is when there's no `@lane_view` yet —
the cold-start-offline state, where there's nothing on screen worth protecting and
the cascade is exactly the recovery path. Every user callback is wrapped in
`App#interaction`, which `touch`es the clock; that's the whole reason a background
reload can't land on a row mid-click, so keep new callbacks wrapped.

**Tags span the whole lane; the leaf view doesn't.** The lane fetch is a single
`TrelloClient#cards_with_checklists` request — cards + checklists + check-items
nested, no per-card fan-out. `BoardFetch` derives two things from that one
payload: the default leaf view (still **first-card-only**) and a lane-wide tag
index (`@words` in checklist names → incomplete items across **every card**),
both carried on the returned `LaneView`. Untagged checklists index under the
`BoardFetch::UNTAGGED` pseudo-tag `<no tag>`, which stands alone in a lane with
no real tags (it still widens the first-card default view to the whole lane).
Toggling tag chips filters in memory via
`LaneView#result_for` — no refetch. The selected-tag set lives on `App`: it
**persists across Refresh** (reconciled against the lane's current tags, vanished
ones dropped) and **resets on a board/lane switch** (a different tag set).

**Random mode is a third view over the same in-memory lane**, not a fetch mode.
The footer's dice draws `view.random_count` items from `LaneView#pool` — the
selected tags' items, or the whole lane when no chip is pressed, de-duplicated by
id so a doubly-tagged item gets no extra chance — and `result_for(…, ids:)`
renders them grouped under the tags they came from. Two consequences worth
knowing: an item whose checklist carries two tags shows under both headings (so
the rows can slightly outnumber the pick — accepted, matching how the tag filter
already behaves), and `limit` is ignored in this mode because the pick size *is*
the cap. `App` holds the pick as **item ids** and re-rolls at exactly four
points: the dice, a pick-size change, a tag change, and every `finish_lane` — so
Refresh and the idle auto-refresh both deal a fresh hand, while ticking rows off
(which doesn't re-render) leaves the hand alone. The count is persisted; the mode
deliberately isn't, so a launch always shows the real list.

## Architecture map

- `bin/todo-sidebar` — entry point (also writes/clears the pidfile).
- `lib/app.rb` — orchestrator: drives the board → lane → fetch cascade, all async.
- `lib/config.rb` — config file load/save.
- `lib/pid_file.rb` — pidfile the app records and `rake sidebar:*` reads.
- `lib/sidebar_control.rb` — start/stop/restart logic behind the `sidebar:*` tasks.
- `lib/trello_client.rb` — Trello REST (stdlib net/http).
- `lib/board_fetch.rb` — builds the view model (the structs the UI renders) and
  the lane-wide tag index (`LaneView`, with in-memory `result_for` filtering).
- `lib/sync.rb` — worker-thread + main-thread marshalling helper.
- `lib/auto_refresh.rb` — the idle clock behind auto-refresh (`touch` on every
  interaction, fires once the interval has elapsed, and again each interval after).
- `lib/x11/strut.rb` — the Xlib strut call. `lib/x11/active_window.rb` — the Xlib
  `_NET_ACTIVE_WINDOW` read for the focused-dot ring.
- `lib/ui/` — `dock_window` (window + strut, and the one CSS provider),
  `styles` (the stylesheet itself, built around a base font size), `header`,
  `dropdown`, `tag_bar` (the `@tag` filter chips), `checklist_view`, `item_row`,
  `limit_bar` (the bottom bar: the items-per-list cap, persisted as
  `view.item_limit` and applied in-memory via `LaneView#result_for(…, limit:)`,
  the dice — whose caption and dropdown take over the cap's, meaning "how many
  to pick" while it's pressed — plus the `A−`/`A+` text-size steppers, persisted
  as `appearance.font_size`),
  `session_bar` + `session_dot` (the Claude-session footer dots).
- `lib/sessions/` — `store` (reads/reaps the hook's state files into `Session`
  structs), `watcher` (the 1s poll loop), `focus` (shells out to the hook).
- `bin/claude-session-tracker` — the Bash hook Claude Code invokes on session
  lifecycle events; writes per-session JSON to
  `~/.local/state/claude-sessions/`. `scripts/install-session-hook.sh` symlinks
  it onto PATH and merges the hooks into `~/.claude/settings.json`.

## The session dots

Two halves talk through JSON files in `~/.local/state/claude-sessions/`. The
**hook** (`bin/claude-session-tracker`, language-agnostic Bash) is wired into
Claude Code's lifecycle hooks and writes `<session_id>.json` with status, theme
color (from the project's `.terminal-theme`), pid, and the terminal's X window
id. The **sidebar** polls that dir (`Sessions::Watcher`), reaps sessions whose
pid has no `/proc` entry (`Sessions::Store`), and renders a dot per session in
two places: the expanded footer (a `FlowBox`) and the collapsed strip (a thin
column). Active sessions pulse; permission ones get a white ring; the one whose
window is focused gets a white inner dot. Both sinks set `no_show_all` and are
hidden when there are no sessions, so the footer leaves no empty strip behind.
Strip dots are non-reactive so a click still expands the strip; footer dots
shell out to the hook's `focus` action to raise (and tab-switch to) the terminal.
