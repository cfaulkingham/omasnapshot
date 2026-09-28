#!/usr/bin/bash
# Install OmaSnapshot on this Omarchy machine:
#   1. copy the plugin into ~/.config/omarchy/plugins/
#   2. enable it, which places the Camera button on the bar
#   3. add Trigger → Capture → Camera and Super+Alt+C
#
# Safe to re-run. --remove-desktop removes only the marked menu and bind blocks.
# An earlier enable that only listed the plugin under plugins[] does not put
# the button on the bar; this script disables that entry and places it.

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
JQ=/usr/bin/jq

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

camera_on_bar() {
  "$OMARCHY_SHELL" shell listShellConfig | "$JQ" -e --arg id "$PLUGIN_ID" '
    ((.bar // {}) | (.layout // {}) | [(.left // []), (.center // []), (.right // [])])
    | add
    | any(
        (
          if type == "object" then (.id // "")
          elif type == "string" then .
          else "" end
        ) == $id
      )
  ' >/dev/null
}

wait_for_bar_widget() {
  local attempt
  for (( attempt = 0; attempt < 40; attempt++ )); do
    if "$OMARCHY" plugin list --json | "$JQ" -e --arg id "$PLUGIN_ID" '
      any(.[]; .id == $id and ((.kinds // []) | index("bar-widget")))
    ' >/dev/null; then
      return 0
    fi
    /usr/bin/sleep 0.05
  done
  echo "install.sh: $PLUGIN_ID was not rescanned as a bar widget" >&2
  return 1
}

enable_plugin() {
  need_exe "$OMARCHY"
  need_exe "$OMARCHY_SHELL"
  need_exe "$JQ"
  "$OMARCHY_SHELL" shell rescanPlugins >/dev/null 2>&1 || true
  wait_for_bar_widget
  "$OMARCHY" plugin enable "$PLUGIN_ID"
  # A plugin enabled before it had a bar widget sits in plugins[] and a second
  # enable leaves it there. Drop that entry, then place the button.
  if camera_on_bar; then
    return 0
  fi
  "$OMARCHY" plugin disable "$PLUGIN_ID"
  "$OMARCHY" plugin enable "$PLUGIN_ID" --section right
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
  echo "Camera is on the bar. Click it to open the overlay."
fi

if ! $PLUGIN_ONLY; then
  edit_desktop add
  echo "Added Trigger → Capture → Camera and Super+Alt+C"
fi
