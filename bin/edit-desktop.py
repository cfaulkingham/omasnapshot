#!/usr/bin/python3 -I
"""Add or remove the OmaSnapshot menu row and Super+Alt+C bind."""

import os
import re
import select
import signal
import stat
import subprocess
import sys
import time
import secrets

MAX = 1_048_576
HYPRCTL = "/usr/bin/hyprctl"
READ_FLAGS = (
    os.O_RDONLY
    | os.O_NOFOLLOW
    | os.O_NONBLOCK
    | os.O_CLOEXEC
)
BIND_RE = re.compile(
    r"-- omasnapshot \(install.sh\)\n"
    r"o\.bind\(\"SUPER \+ ALT \+ C\", \"OmaSnapshot\", .*?\)\n?",
)
MENU_RE = re.compile(
    r"\n[ \t]*// -- omasnapshot \(install.sh\).*?// -- omasnapshot end\n?",
    re.S,
)
START_BIND = "-- omasnapshot (install.sh)"
START_MENU = "// -- omasnapshot (install.sh)"
END_MENU = "// -- omasnapshot end"


def bind_block(bind_keys, plugin_id):
    return (
        "-- omasnapshot (install.sh)\n"
        f'o.bind("{bind_keys}", "OmaSnapshot", '
        f'"omarchy-shell shell toggle {plugin_id} \'{{}}\'")\n'
    )


def menu_block(plugin_id):
    return (
        "\n"
        "  // -- omasnapshot (install.sh)\n"
        f'  "trigger.capture.camera": {{"icon":"󰄀","label":"Camera",'
        f'"description":"Take a photo or record a video with the webcam",'
        f'"when":"omarchy-hw-webcam",'
        f'"action":"omarchy-shell shell toggle {plugin_id} \'{{}}\'"}}\n'
        "  // -- omasnapshot end\n"
    )


def read_file(path):
    try:
        fd = os.open(path, READ_FLAGS)
    except FileNotFoundError:
        return None, None
    except OSError as exc:
        raise SystemExit(f"install.sh: refusing {path}: {exc.strerror}") from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise SystemExit(f"install.sh: refusing {path}: not a regular file")
        if info.st_uid != os.geteuid():
            raise SystemExit(f"install.sh: refusing {path}: unexpected owner")
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
        return data.decode("utf-8", "strict"), stat.S_IMODE(info.st_mode)
    finally:
        os.close(fd)


def _open_parent_dir(path):
    directory = os.path.dirname(path) or "."
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
    try:
        return os.open(directory, flags | os.O_NOFOLLOW)
    except OSError:
        return os.open(directory, flags)


def atomic_write(path, text, mode):
    payload = text.encode("utf-8")
    if len(payload) > MAX:
        raise SystemExit(f"install.sh: refusing to write {path}: too large")
    name = os.path.basename(path)
    dirfd = _open_parent_dir(path)
    tmp = f".omasnapshot.{secrets.token_hex(8)}.tmp"
    fd = None
    try:
        fd = os.open(
            tmp,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
            dir_fd=dirfd,
        )
        os.fchmod(fd, mode)
        view = memoryview(payload)
        while view:
            n = os.write(fd, view)
            view = view[n:]
        os.fsync(fd)
        os.rename(tmp, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        os.fsync(dirfd)
        tmp = None
    except OSError as exc:
        raise SystemExit(f"install.sh: write failed for {path}: {exc.strerror}") from exc
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp, dir_fd=dirfd)
            except OSError:
                pass
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
        os.close(dirfd)


def unlink_created(path):
    try:
        fd = os.open(path, READ_FLAGS)
    except FileNotFoundError:
        return
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            return
    finally:
        os.close(fd)
    try:
        os.unlink(path)
    except OSError:
        pass


def ensure_dir(path, mode=0o755):
    if os.path.isdir(path):
        st = os.stat(path)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
            raise SystemExit(f"install.sh: refusing {path}: unexpected owner")
        return
    if os.path.lexists(path):
        raise SystemExit(f"install.sh: refusing {path}: not a directory")
    parent = os.path.dirname(path)
    if parent and parent != path:
        ensure_dir(parent, mode)
    try:
        os.mkdir(path, mode)
    except FileExistsError:
        if not os.path.isdir(path):
            raise SystemExit(f"install.sh: refusing {path}: not a directory")


def assert_bind_markers(text):
    starts = text.count(START_BIND)
    matches = len(BIND_RE.findall(text))
    if starts != matches:
        raise SystemExit("install.sh: malformed omasnapshot bind marker")
    if starts > 1:
        raise SystemExit("install.sh: duplicate omasnapshot bind markers")


def assert_menu_markers(text):
    starts = text.count(START_MENU)
    ends = text.count(END_MENU)
    matches = len(MENU_RE.findall(text))
    if starts != ends or starts != matches:
        raise SystemExit("install.sh: malformed omasnapshot menu markers")
    if starts > 1:
        raise SystemExit("install.sh: duplicate omasnapshot menu markers")


def add_bind(text, bind_keys, plugin_id):
    text = BIND_RE.sub("", text)
    if not text.endswith("\n"):
        text += "\n"
    return text + bind_block(bind_keys, plugin_id)


def remove_bind(text):
    return BIND_RE.sub("", text)


def add_menu(text, plugin_id):
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
    return head + "\n" + menu_block(plugin_id) + "}\n"


def remove_menu(text):
    return MENU_RE.sub("\n", text)


def _hypr_env():
    env = {
        "PATH": "/usr/bin:/bin",
        "LC_ALL": "C",
    }
    for key in ("HOME", "USER", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
        value = os.environ.get(key)
        if value:
            env[key] = value
    return env


def run_bounded(argv, timeout=8, max_out=65536):
    p = subprocess.Popen(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        env=_hypr_env(),
        close_fds=True,
    )
    out = b""
    err = b""
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                    time.sleep(1)
                    os.killpg(p.pid, signal.SIGKILL)
                except OSError:
                    pass
                p.wait()
                return 124, b"", b"timeout"
            pipes = [fd for fd in (p.stdout, p.stderr) if fd is not None]
            ready, _, _ = select.select(pipes, [], [], min(remaining, 0.2))
            if p.stdout in ready:
                chunk = os.read(p.stdout.fileno(), 4096)
                if chunk:
                    out += chunk[: max(0, max_out + 1 - len(out))]
                else:
                    p.stdout.close()
                    p.stdout = None
            if p.stderr in ready:
                chunk = os.read(p.stderr.fileno(), 4096)
                if chunk:
                    err += chunk[: max(0, max_out + 1 - len(err))]
                else:
                    p.stderr.close()
                    p.stderr = None
            if p.poll() is not None:
                for attr in ("stdout", "stderr"):
                    stream = getattr(p, attr)
                    if stream is None:
                        continue
                    rest = stream.read(max_out + 1)
                    if attr == "stdout":
                        out += rest[: max(0, max_out + 1 - len(out))]
                    else:
                        err += rest[: max(0, max_out + 1 - len(err))]
                    stream.close()
                    setattr(p, attr, None)
                break
        return p.wait(), out[:max_out], err[:max_out]
    except BaseException:
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            p.wait()
        raise


def hypr_reload_or_rollback(bind_path, previous_text, previous_mode):
    if not os.path.isfile(HYPRCTL):
        return
    rc, _out, err = run_bounded([HYPRCTL, "reload"])
    if rc != 0:
        # Compositor not running is not a write failure.
        if b"couldn't connect" in err.lower() or b"no such file" in err.lower() or rc == 124:
            return
        raise SystemExit("install.sh: hyprctl reload failed")
    rc, out, _err = run_bounded([HYPRCTL, "configerrors"])
    if rc != 0:
        return
    if out.strip():
        if previous_text is None:
            unlink_created(bind_path)
        else:
            atomic_write(bind_path, previous_text, previous_mode)
        run_bounded([HYPRCTL, "reload"])
        raise SystemExit("install.sh: hypr configerrors after bind change, rolled back")


def apply(bind_path, menu_path, action, bind_keys, plugin_id, reload_hypr=True):
    if action not in ("add", "remove"):
        raise SystemExit(f"install.sh: unknown desktop action {action}")
    if not re.fullmatch(r"[A-Za-z0-9]+(\.[A-Za-z0-9]+)+", plugin_id):
        raise SystemExit("install.sh: invalid plugin id")
    if bind_keys != "SUPER + ALT + C":
        raise SystemExit("install.sh: unexpected bind keys")

    bind_text, bind_mode = read_file(bind_path)
    if bind_text is None:
        raise SystemExit(f"install.sh: missing {bind_path}")
    assert_bind_markers(bind_text)

    menu_parent = os.path.dirname(menu_path)
    ensure_dir(menu_parent)
    menu_text, menu_mode = read_file(menu_path)
    menu_existed = menu_text is not None
    if menu_text is None:
        menu_text = "{\n}\n"
        menu_mode = 0o644
    assert_menu_markers(menu_text)

    previous_bind = bind_text
    previous_bind_mode = bind_mode
    previous_menu = menu_text if menu_existed else None
    previous_menu_mode = menu_mode if menu_existed else None

    if action == "add":
        new_bind = add_bind(bind_text, bind_keys, plugin_id)
        new_menu = add_menu(menu_text, plugin_id)
    else:
        new_bind = remove_bind(bind_text)
        new_menu = remove_menu(menu_text)

    wrote_bind = False
    wrote_menu = False
    try:
        atomic_write(bind_path, new_bind, bind_mode)
        wrote_bind = True
        atomic_write(menu_path, new_menu, menu_mode)
        wrote_menu = True
        if reload_hypr:
            hypr_reload_or_rollback(bind_path, previous_bind, previous_bind_mode)
    except SystemExit:
        if wrote_bind:
            atomic_write(bind_path, previous_bind, previous_bind_mode)
        if wrote_menu:
            if previous_menu is None:
                unlink_created(menu_path)
            else:
                atomic_write(menu_path, previous_menu, previous_menu_mode)
        raise


def main(argv):
    if len(argv) != 6:
        return 2
    apply(argv[1], argv[2], argv[3], argv[4], argv[5])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(exc.code, file=sys.stderr)
            sys.exit(1)
        raise
