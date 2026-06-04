#!/usr/bin/env bash
# Installs a Cinnamon autostart entry so the todo sidebar launches on login.
# Absolute paths are baked in now, so it doesn't depend on PATH at login time.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve a concrete ruby binary that works standalone at login.
# NOT a mise *shim* — shims need a version config that may be unset for the
# login session and fail with "No version is set for shim: ruby". `mise which`
# (or an activated PATH) gives the real install path, which runs on its own.
if command -v mise >/dev/null 2>&1 && RUBY_BIN="$(mise which ruby 2>/dev/null)"; then
  :
else
  RUBY_BIN="$(command -v ruby || true)"
fi

case "$RUBY_BIN" in
  */mise/shims/*) RUBY_BIN="" ;; # never bake a shim
esac

if [ -z "$RUBY_BIN" ] || [ ! -x "$RUBY_BIN" ]; then
  echo "error: could not resolve a standalone ruby binary (avoid mise shims)" >&2
  exit 1
fi

AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/cinnamon-subsequent.desktop"
mkdir -p "$AUTOSTART_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Todo Sidebar
Comment=Persistent Trello checklist sidebar
Exec=$RUBY_BIN $PROJECT_DIR/bin/todo-sidebar
Path=$PROJECT_DIR
X-GNOME-Autostart-enabled=true
NoDisplay=true
Terminal=false
EOF

echo "Installed autostart entry:"
echo "  $DESKTOP_FILE"
echo "  Exec=$RUBY_BIN $PROJECT_DIR/bin/todo-sidebar"
echo
echo "It will start on next login. To start it now without logging out:"
echo "  $RUBY_BIN $PROJECT_DIR/bin/todo-sidebar &"
echo "To remove autostart: rm \"$DESKTOP_FILE\""
