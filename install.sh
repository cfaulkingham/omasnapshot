#!/usr/bin/env bash
# Install OmaSnapshot on this Omarchy machine:
#   1. copy the overlay plugin into ~/.config/omarchy/plugins/
#   2. enable it
#   3. add Trigger → Capture → Camera and Super+Alt+C
#
# Safe to re-run. --remove-desktop removes only the marked menu and bind blocks.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="io.github.cfaulkingham.omasnapshot"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
BINDINGS_LUA="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
MENU_JSONC="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc"
BIND_KEYS="SUPER + ALT + C"
USAGE="Usage: ./install.sh [--plugin-only|--desktop-only|--remove-desktop]"

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

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "install.sh: missing required command: $1" >&2
    exit 1
  }
}

copy_plugin() {
  need rsync
  mkdir -p "$PLUGIN_DIR"
  if [[ $ROOT != "$PLUGIN_DIR" ]]; then
    rsync -a --delete --exclude .git --exclude test "$ROOT/" "$PLUGIN_DIR/"
  fi
}

enable_plugin() {
  need omarchy
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable "$PLUGIN_ID"
}

edit_desktop() {
  local action=$1
  python3 - "$BINDINGS_LUA" "$MENU_JSONC" "$action" "$BIND_KEYS" "$PLUGIN_ID" <<'PY'
import os
import re
import stat
import sys
import tempfile

bind_path, menu_path, action, bind_keys, plugin_id = sys.argv[1:6]
MAX = 1_048_576
flags = (
    os.O_RDONLY
    | getattr(os, "O_NOFOLLOW", 0)
    | getattr(os, "O_NONBLOCK", 0)
    | getattr(os, "O_CLOEXEC", 0)
)
BIND = (
    "-- omasnapshot (install.sh)\n"
    f'o.bind("{bind_keys}", "OmaSnapshot", "omarchy-shell shell toggle {plugin_id} \'{{}}\'")\n'
)
BIND_RE = re.compile(
    r"-- omasnapshot \(install.sh\)\n"
    r"o\.bind\(\"SUPER \+ ALT \+ C\", \"OmaSnapshot\", .*?\)\n?",
)
MENU_RE = re.compile(
    r"\n[ \t]*// -- omasnapshot \(install.sh\).*?// -- omasnapshot end\n?",
    re.S,
)
MENU_BLOCK = f'''
  // -- omasnapshot (install.sh)
  "trigger.capture.camera": {{"icon":"󰄀","label":"Camera","description":"Take a photo or record a video with the webcam","when":"omarchy-hw-webcam","action":"omarchy-shell shell toggle {plugin_id} '{{}}'"}}
  // -- omasnapshot end
'''


def read_file(path):
    if not os.path.exists(path):
        return ""
    fd = os.open(path, flags)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise SystemExit(f"install.sh: refusing {path}: not a regular file")
        if info.st_size > MAX:
            raise SystemExit(f"install.sh: refusing {path}: too large")
        os.set_blocking(fd, True)
        data = b""
        while len(data) <= MAX:
            chunk = os.read(fd, min(65536, MAX + 1 - len(data)))
            if not chunk:
                break
            data += chunk
        if len(data) > MAX:
            raise SystemExit(f"install.sh: refusing {path}: too large")
        return data.decode()
    finally:
        os.close(fd)


def atomic_write(path, text):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".omasnapshot.", dir=directory)
    try:
        if os.path.exists(path):
            os.fchmod(fd, stat.S_IMODE(os.stat(path).st_mode))
        os.write(fd, text.encode())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


def add_bind(text):
    text = BIND_RE.sub("", text)
    if not text.endswith("\n"):
        text += "\n"
    return text + BIND


def remove_bind(text):
    return BIND_RE.sub("", text)


def add_menu(text):
    if not text.strip():
        text = "{\n}\n"
    text = MENU_RE.sub("\n", text)
    idx = text.rfind("}")
    if idx == -1:
        raise SystemExit("install.sh: omarchy-menu.jsonc has no closing brace")
    head = text[:idx].rstrip()
    stripped = re.sub(r"//.*?$", "", head, flags=re.M).rstrip()
    if stripped and not stripped.endswith("{") and not stripped.endswith(","):
        head += ","
    return head + "\n" + MENU_BLOCK + "}\n"


def remove_menu(text):
    return MENU_RE.sub("\n", text)


bind_text = read_file(bind_path)
menu_text = read_file(menu_path)
if action == "add":
    atomic_write(bind_path, add_bind(bind_text))
    atomic_write(menu_path, add_menu(menu_text))
elif action == "remove":
    if os.path.exists(bind_path):
        atomic_write(bind_path, remove_bind(bind_text))
    if os.path.exists(menu_path):
        atomic_write(menu_path, remove_menu(menu_text))
else:
    raise SystemExit(f"install.sh: unknown desktop action {action}")
PY
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
  need python3
  mkdir -p "$(dirname "$MENU_JSONC")"
  [[ -f $BINDINGS_LUA ]] || {
    echo "install.sh: missing $BINDINGS_LUA" >&2
    exit 1
  }
  [[ -f $MENU_JSONC ]] || printf '%s\n' '{' '}' >"$MENU_JSONC"
  edit_desktop add
  echo "Added Trigger → Capture → Camera and Super+Alt+C"
fi
