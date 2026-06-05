# cinnamon-subsequent

> Working on the code (human or AI agent)? Read [AGENTS.md](AGENTS.md) first — it
> captures the non-obvious constraints and gotchas.

A persistent to-do **sidebar** for the Linux Mint / Cinnamon desktop, backed by
Trello. It pins a full-height column to the right edge of the screen that:

- **reserves its space** — maximized windows stop at it instead of covering it;
- shows on **all workspaces**, stays **below** normal windows, and never grabs
  focus or appears in the taskbar / Alt-Tab;
- renders the checklists of the **first card** in a chosen board + lane, showing
  only **incomplete** items;
- lets you **click an item to complete it** (pushed to Trello immediately, with a
  spinner while it's in flight and undo by clicking again);
- lets you **filter by `@tag`** — a wrapping row of tag chips sits under the menu
  (a tag is any `@word` in a checklist's name); click chips to show matching
  incomplete items from **every card in the lane**, each selected tag under its
  own heading. With nothing selected you get the normal first-card view.
- has **Board** and **Lane** dropdowns and a **Refresh** button up top (Refresh
  reloads everything — boards, lanes, and the card).

It's deliberately X11-only (Cinnamon/Muffin is X11) and GTK **3** (GTK4 dropped
the window-manager hint APIs a dock needs).

## Requirements

- Linux Mint / Cinnamon on **X11**
- Ruby (any recent version; developed on a mise-managed Ruby)
- GTK 3 development headers, to build the `gtk3` gem:
  ```
  sudo apt install libgtk-3-dev
  ```

## Setup

1. **Install gems** (into the active Ruby's global gemset — *not* vendored; the
   repo lives in Dropbox and shouldn't sync compiled extensions, see
   [AGENTS.md](AGENTS.md)):
   ```
   bundle install
   ```

2. **Get Trello credentials.** Create an API key at
   <https://trello.com/power-ups/admin>, then mint a token (scope `read,write`):
   ```
   https://trello.com/1/authorize?expiration=never&scope=read,write&response_type=token&name=Cinnamon%20Sidebar&key=YOUR_API_KEY
   ```

3. **Write the config.** Copy the example and fill in your key/token:
   ```
   mkdir -p ~/.config/cinnamon-subsequent
   cp config.example.json ~/.config/cinnamon-subsequent/config.json
   chmod 600 ~/.config/cinnamon-subsequent/config.json
   $EDITOR ~/.config/cinnamon-subsequent/config.json
   ```

4. **Run it:**
   ```
   bin/todo-sidebar
   ```
   Pick your board and lane from the dropdowns; the selection is remembered.

## Config

`~/.config/cinnamon-subsequent/config.json` (kept `0600`, it holds your token):

| Field                  | Meaning                                           |
| ---------------------- | ------------------------------------------------- |
| `trello.key` / `.token`| Trello API credentials                            |
| `selection.board_id`   | Persisted board (set automatically as you pick)   |
| `selection.lane_id`    | Persisted lane                                    |
| `appearance.edge`      | Currently `right`                                 |
| `appearance.width`     | Sidebar width in (logical) pixels, default `320`  |

## Autostart on login

```
./scripts/install-autostart.sh
```

This bakes absolute paths into `~/.config/autostart/cinnamon-subsequent.desktop`
so it launches reliably at login (independent of your shell's PATH). Remove it
with:

```
rm ~/.config/autostart/cinnamon-subsequent.desktop
```

## Notes

- **HiDPI:** the strut is scaled by the monitor's `scale_factor`, so the reserved
  width matches the on-screen width on 2× displays.
- The sidebar reads the **first card** of the selected lane; its checklists become
  the list. Completed items stay visible (struck-through, undoable) until the next
  **Refresh**.
- **Tags are lane-scoped.** The chips come from `@words` in checklist names across
  every card in the current lane; the bar hides itself when a lane has no `@tags`.
  The selection survives a Refresh but resets when you switch board or lane.
- **Refresh** reloads the whole cascade — boards, lanes, and the card (refetching
  incomplete-only) — while keeping your current selection. This is also the
  recovery path when the sidebar starts with **no network**: it shows an error and
  empty dropdowns, and a single **Refresh** once you're online fills everything in.
