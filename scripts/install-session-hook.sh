#!/usr/bin/env bash
# Installs the Claude Code session hook: symlinks the bin/claude-session-tracker
# script onto PATH, creates the state directory the sidebar reads, and merges
# the lifecycle hooks into ~/.claude/settings.json so Claude Code reports
# session state. The dots themselves are drawn by the sidebar (bin/todo-sidebar),
# which replaces the old standalone Cinnamon extension.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Dependencies the hook shells out to.
for cmd in xdotool jq wmctrl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed."
    echo "  sudo apt install $cmd"
    exit 1
  fi
done

# Symlink the hook onto PATH so Claude Code can invoke it by name.
mkdir -p "$HOME/.local/bin"
ln -sf "$PROJECT_DIR/bin/claude-session-tracker" "$HOME/.local/bin/claude-session-tracker"
chmod +x "$PROJECT_DIR/bin/claude-session-tracker"
echo "Linked claude-session-tracker → ~/.local/bin/"

# Retire the old standalone Cinnamon extension if a previous install left it
# behind — the sidebar renders the dots now, and two of them would overlap.
OLD_EXTENSION="$HOME/.local/share/cinnamon/extensions/claude-sessions@fletch"
if [ -L "$OLD_EXTENSION" ] || [ -e "$OLD_EXTENSION" ]; then
  rm -f "$OLD_EXTENSION"
  echo "Removed the old claude-sessions Cinnamon extension (the sidebar draws the dots now)"
fi

# State directory the hook writes and the sidebar polls.
mkdir -p "$HOME/.local/state/claude-sessions"
echo "Created ~/.local/state/claude-sessions/"

# Merge the lifecycle hooks into Claude Code's settings, preserving any others.
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  BACKUP="${SETTINGS}.backup.$(date +%s)"
  cp "$SETTINGS" "$BACKUP"
  echo "Backed up settings to $BACKUP"

  jq '
    def remove_tracker($event):
      if .hooks[$event] then
        .hooks[$event] |= [.[] | select((.hooks // []) | all(.command | test("claude-session-tracker") | not))]
      else . end;

    def append_hook($event; $entry):
      .hooks[$event] = ((.hooks[$event] // []) + [$entry]);

    .hooks //= {}
    | remove_tracker("SessionStart")
    | remove_tracker("Notification")
    | remove_tracker("Stop")
    | remove_tracker("PostToolUse")
    | remove_tracker("UserPromptSubmit")
    | remove_tracker("SessionEnd")
    | append_hook("SessionStart";
        {"hooks": [{"type": "command", "command": "claude-session-tracker session-start"}]})
    | append_hook("Notification";
        {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "claude-session-tracker notification-permission"}]})
    | append_hook("PostToolUse";
        {"hooks": [{"type": "command", "command": "claude-session-tracker tool-active"}]})
    | append_hook("Stop";
        {"hooks": [{"type": "command", "command": "claude-session-tracker notification-idle"}]})
    | append_hook("UserPromptSubmit";
        {"hooks": [{"type": "command", "command": "claude-session-tracker prompt-submit"}]})
    | append_hook("SessionEnd";
        {"hooks": [{"type": "command", "command": "claude-session-tracker session-end"}]})
  ' "$SETTINGS" > "${SETTINGS}.tmp"
  mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "Updated Claude hooks in settings.json"
else
  echo "Warning: $SETTINGS not found, skipping hook setup"
fi

echo ""
echo "Done. Session dots will appear in the sidebar footer once you start a"
echo "Claude Code session (the sidebar must be running — see ./scripts/install-autostart.sh)."
