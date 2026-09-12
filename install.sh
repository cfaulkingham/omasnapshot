#!/usr/bin/bash
# Install OmaSnapshot on this Omarchy machine:
#   1. copy the overlay plugin into ~/.config/omarchy/plugins/
#   2. enable it
#   3. add Trigger → Capture → Camera and Super+Alt+C
#
# Safe to re-run. --remove-desktop removes only the marked menu and bind blocks.

set -euo pipefail

: "${HOME:?}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.cfaulkingham.omasnapshot"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
BINDINGS_LUA="$CONFIG_HOME/hypr/bindings.lua"
MENU_JSONC="$CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
BIND_KEYS="SUPER + ALT + C"
USAGE="Usage: ./install.sh [--plugin-only|--desktop-only|--remove-desktop]"
PYTHON=/usr/bin/python3
RSYNC=/usr/bin/rsync
MKDIR=/usr/bin/mkdir
OMARCHY=/usr/bin/omarchy
OMARCHY_SHELL=/usr/bin/omarchy-shell

PLUGIN_ONLY=false
DESKTOP_ONLY=false
REMOVE_DESKTOP=false
case "${1:-}" in
  --plugin-only) PLUGIN_ONLY=true ;;
  --desktop-only) DESKTOP_ONLY=true ;;
  --remove-desktop) REMOVE_DESKTOP=true ;;
  "") ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "$USAGE" >&2; exit 2; }
[[ $(uname -s) == Linux ]] || { echo "OmaSnapshot installation requires Linux with Omarchy." >&2; exit 1; }

need_exe() {
  local path=$1
  [[ -x "$path" ]] || {
    echo "install.sh: missing required command: $path" >&2
    exit 1
  }
}

copy_plugin() {
  need_exe "$RSYNC"
  need_exe "$MKDIR"
  if [[ -L "$PLUGIN_DIR" ]]; then
    echo "install.sh: refusing $PLUGIN_DIR: symlink" >&2
    exit 1
  fi
  "$MKDIR" -p -- "$CONFIG_HOME/omarchy/plugins"
  if [[ -e "$PLUGIN_DIR" && ! -d "$PLUGIN_DIR" ]]; then
    echo "install.sh: refusing $PLUGIN_DIR: not a directory" >&2
    exit 1
  fi
  "$MKDIR" -p -- "$PLUGIN_DIR"
  if [[ -L "$PLUGIN_DIR" ]]; then
    echo "install.sh: refusing $PLUGIN_DIR: symlink" >&2
    exit 1
  fi
  if [[ "$ROOT" != "$PLUGIN_DIR" ]]; then
    "$RSYNC" -a --delete --exclude .git --exclude test --exclude __pycache__ --exclude '*.pyc' "$ROOT/" "$PLUGIN_DIR/"
  fi
}

enable_plugin() {
  need_exe "$OMARCHY"
  if [[ -x $OMARCHY_SHELL ]]; then
    "$OMARCHY_SHELL" shell rescanPlugins >/dev/null 2>&1 || true
  fi
  "$OMARCHY" plugin enable "$PLUGIN_ID"
}

edit_desktop() {
  local action=$1
  need_exe "$PYTHON"
  [[ -f "$ROOT/bin/edit-desktop.py" ]] || {
    echo "install.sh: missing $ROOT/bin/edit-desktop.py" >&2
    exit 1
  }
  [[ -f "$BINDINGS_LUA" && ! -L "$BINDINGS_LUA" ]] || {
    echo "install.sh: missing regular file $BINDINGS_LUA" >&2
    exit 1
  }
  "$PYTHON" -I -S "$ROOT/bin/edit-desktop.py" "$BINDINGS_LUA" "$MENU_JSONC" "$action" "$BIND_KEYS" "$PLUGIN_ID"
}

if $REMOVE_DESKTOP; then
  edit_desktop remove
  echo "Removed OmaSnapshot menu row and Super+Alt+C."
  exit 0
fi

if ! $DESKTOP_ONLY; then
  copy_plugin
  enable_plugin
  echo "Installed plugin $PLUGIN_ID"
fi

if ! $PLUGIN_ONLY; then
  edit_desktop add
  echo "Added Trigger → Capture → Camera and Super+Alt+C"
fi
