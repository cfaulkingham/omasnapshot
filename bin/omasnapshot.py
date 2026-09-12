#!/usr/bin/python3 -I
"""Descriptor-bound helper for OmaSnapshot settings, xdg dirs, and gamma."""

import json
import os
import pwd
import re
import select
import signal
import stat
import subprocess
import sys
import time
import secrets

MAX_SETTINGS = 4096
MAX_XDG = 4096
MAX_PATH = 4096
PHOTO_MAX = 64 * 1024 * 1024
VIDEO_MAX = 2 * 1024 * 1024 * 1024
PHOTO_DEADLINE = 30
VIDEO_DEADLINE = 180
ERR_MAX = 4096
FFMPEG = "/usr/bin/ffmpeg"
XDG_USER_DIR = "/usr/bin/xdg-user-dir"
_COMPONENT = re.compile(r"[A-Za-z0-9._-]+")
_SETTINGS_NAME = "settings.json"
_GAMMA_RE = re.compile(r"^[0-9]+(\.[0-9]{1,2})?$")
_BASE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")


def _ok_component(name):
    return bool(_COMPONENT.fullmatch(name)) and name not in (".", "..")


def clamp_gamma(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return 1.0
    if n != n or n in (float("inf"), float("-inf")):
        return 1.0
    n = min(2.0, max(0.5, n))
    return round(n * 20) / 20


def parse_gamma(text):
    raw = str(text)
    if len(raw) > 8 or not _GAMMA_RE.fullmatch(raw):
        raise ValueError("invalid gamma")
    return clamp_gamma(raw)


def usable_abs_path(path):
    if not isinstance(path, str) or not path.startswith("/") or len(path) > MAX_PATH:
        return False
    if "\0" in path or "\r" in path or "\n" in path:
        return False
    parts = path.split("/")
    for i, part in enumerate(parts):
        if i == 0 and part == "":
            continue
        if not part or part in (".", ".."):
            return False
    return True


def open_dir_chain(parts, home=None):
    if not parts or not all(_ok_component(p) for p in parts):
        raise PermissionError("refusing directory chain")
    if home is None:
        home = pwd.getpwuid(os.geteuid()).pw_dir
    fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for i, name in enumerate(parts):
            try:
                nfd = os.open(
                    name,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                    dir_fd=fd,
                )
            except FileNotFoundError:
                try:
                    os.mkdir(name, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                nfd = os.open(
                    name,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                    dir_fd=fd,
                )
            os.close(fd)
            fd = nfd
            st = os.fstat(fd)
            if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
                raise PermissionError(f"untrusted directory component {name}")
            if i == len(parts) - 1 and st.st_mode & 0o077:
                os.fchmod(fd, 0o700)
        return fd
    except BaseException:
        os.close(fd)
        raise


def repair_leaf(dirfd):
    for name in os.listdir(dirfd):
        st = os.stat(name, dir_fd=dirfd, follow_symlinks=False)
        if stat.S_ISREG(st.st_mode):
            if name.startswith(".") and name.endswith(".tmp"):
                os.unlink(name, dir_fd=dirfd)
                continue
            if st.st_mode & 0o077:
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dirfd)
                try:
                    os.fchmod(fd, 0o600)
                finally:
                    os.close(fd)
            continue
        try:
            os.unlink(name, dir_fd=dirfd)
        except OSError:
            try:
                os.rmdir(name, dir_fd=dirfd)
            except OSError:
                pass


def read_bounded(dirfd, name, max_bytes=MAX_SETTINGS):
    try:
        fd = os.open(
            name,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
            dir_fd=dirfd,
        )
    except FileNotFoundError:
        return None
    try:
        st = os.fstat(fd)
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.geteuid()
            or st.st_nlink != 1
            or st.st_mode & 0o077
            or st.st_size > max_bytes
        ):
            raise PermissionError("refusing state file (expected 0600, owner-only, one link)")
        os.set_blocking(fd, True)
        data = b""
        while len(data) <= max_bytes:
            chunk = os.read(fd, min(65536, max_bytes + 1 - len(data)))
            if not chunk:
                break
            data += chunk
        if len(data) > max_bytes:
            raise PermissionError("state file grew past the limit")
        return data
    finally:
        os.close(fd)


def write_atomic(dirfd, name, data, max_bytes=MAX_SETTINGS):
    if len(data) > max_bytes:
        raise ValueError("payload too large")
    tmp = f".{name}.{secrets.token_hex(8)}.tmp"
    fd = os.open(
        tmp,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
        dir_fd=dirfd,
    )
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(data)
        while view:
            n = os.write(fd, view)
            view = view[n:]
        os.fsync(fd)
        os.rename(tmp, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        os.fsync(dirfd)
        tmp = None
    except BaseException:
        if tmp is not None:
            try:
                os.unlink(tmp, dir_fd=dirfd)
            except OSError:
                pass
        raise
    finally:
        os.close(fd)


def settings_dirfd(home=None):
    fd = open_dir_chain([".local", "state", "omasnapshot"], home=home)
    try:
        repair_leaf(fd)
    except OSError:
        os.close(fd)
        raise
    return fd


def settings_payload(gamma):
    return (json.dumps({"gamma": clamp_gamma(gamma)}, separators=(",", ":")) + "\n").encode("ascii")


def parse_settings(raw):
    if raw is None:
        return 1.0
    data = json.loads(raw.decode("utf-8", "strict"))
    if not isinstance(data, dict):
        raise ValueError("settings must be an object")
    return clamp_gamma(data.get("gamma", 1))


def cmd_read_settings(home=None):
    dirfd = settings_dirfd(home)
    try:
        raw = read_bounded(dirfd, _SETTINGS_NAME)
        gamma = parse_settings(raw)
    finally:
        os.close(dirfd)
    sys.stdout.write(json.dumps({"gamma": gamma}, separators=(",", ":")) + "\n")


def cmd_write_settings(gamma_text, home=None):
    gamma = parse_gamma(gamma_text)
    dirfd = settings_dirfd(home)
    try:
        write_atomic(dirfd, _SETTINGS_NAME, settings_payload(gamma))
    finally:
        os.close(dirfd)
    sys.stdout.write(json.dumps({"gamma": gamma}, separators=(",", ":")) + "\n")


def _expand_user_path(value, home):
    path = value.strip()
    if path.startswith("$HOME"):
        path = home + path[5:]
    elif path.startswith("~"):
        path = home + path[1:]
    return path.rstrip("/") if len(path) > 1 else path


def _run_bounded(argv, timeout, max_out, env=None):
    p = subprocess.Popen(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        env=env,
        close_fds=True,
    )
    out = b""
    err = b""
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                os.killpg(p.pid, signal.SIGTERM)
                time.sleep(2)
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except OSError:
                    pass
                p.wait()
                raise TimeoutError("command timed out")
            pipes = [fd for fd in (p.stdout, p.stderr) if fd is not None]
            ready, _, _ = select.select(pipes, [], [], min(remaining, 0.2))
            if p.stdout in ready:
                chunk = os.read(p.stdout.fileno(), 4096)
                if chunk:
                    out += chunk
                    if len(out) > max_out:
                        os.killpg(p.pid, signal.SIGTERM)
                        time.sleep(2)
                        try:
                            os.killpg(p.pid, signal.SIGKILL)
                        except OSError:
                            pass
                        p.wait()
                        raise ValueError("output exceeded limit")
                else:
                    p.stdout.close()
                    p.stdout = None
            if p.stderr in ready:
                chunk = os.read(p.stderr.fileno(), 4096)
                if chunk:
                    if len(err) <= ERR_MAX:
                        err += chunk[: ERR_MAX + 1 - len(err)]
                else:
                    p.stderr.close()
                    p.stderr = None
            if p.poll() is not None and p.stdout is None and p.stderr is None:
                break
            if p.poll() is not None:
                for stream_name in ("stdout", "stderr"):
                    stream = getattr(p, stream_name)
                    if stream is None:
                        continue
                    rest = stream.read(max_out + 1)
                    if stream_name == "stdout":
                        out += rest
                    else:
                        err += rest[: max(0, ERR_MAX + 1 - len(err))]
                    stream.close()
                    setattr(p, stream_name, None)
                break
        rc = p.wait()
        if len(out) > max_out:
            raise ValueError("output exceeded limit")
        return rc, out, err
    except BaseException:
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGTERM)
                time.sleep(2)
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            p.wait()
        raise


def _xdg_from_tool(kind, home):
    if not os.path.isfile(XDG_USER_DIR):
        return None
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": home,
        "LC_ALL": "C",
    }
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        env["XDG_RUNTIME_DIR"] = runtime
    rc, out, _err = _run_bounded([XDG_USER_DIR, kind], timeout=5, max_out=MAX_XDG, env=env)
    if rc != 0:
        return None
    path = out.decode("utf-8", "strict").strip()
    return path or None


def resolve_user_dir(kind, home=None, environ=None):
    if kind not in ("PICTURES", "VIDEOS"):
        raise ValueError("invalid user dir")
    if home is None:
        home = pwd.getpwuid(os.geteuid()).pw_dir
    env = os.environ if environ is None else environ
    key = "XDG_PICTURES_DIR" if kind == "PICTURES" else "XDG_VIDEOS_DIR"
    fallback = "Pictures" if kind == "PICTURES" else "Videos"
    raw = env.get(key) or ""
    if raw:
        path = _expand_user_path(raw, home)
        if usable_abs_path(path):
            return path
    tool = _xdg_from_tool(kind, home)
    if tool and usable_abs_path(tool):
        return tool
    path = home.rstrip("/") + "/" + fallback
    if not usable_abs_path(path):
        raise PermissionError("refusing user dir")
    return path


def cmd_xdg_dirs(home=None):
    pictures = resolve_user_dir("PICTURES", home=home)
    videos = resolve_user_dir("VIDEOS", home=home)
    sys.stdout.write(
        json.dumps({"pictures": pictures, "videos": videos}, separators=(",", ":")) + "\n"
    )


def _kill_group(pid):
    try:
        os.killpg(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        try:
            os.killpg(pid, 0)
        except OSError:
            return
        time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except OSError:
        pass


def cmd_gamma(kind, path, gamma_text):
    if kind not in ("photo", "video"):
        raise ValueError("invalid gamma kind")
    if not usable_abs_path(path):
        raise ValueError("invalid path")
    base = os.path.basename(path)
    if not _BASE_RE.fullmatch(base) or base in (".", ".."):
        raise ValueError("invalid filename")
    if not os.path.isfile(FFMPEG):
        raise FileNotFoundError("ffmpeg is not installed")
    gamma = parse_gamma(gamma_text)
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    src_fd = os.open(path, flags)
    tmp_name = None
    dirfd = None
    tmp_fd = None
    try:
        st = os.fstat(src_fd)
        max_size = PHOTO_MAX if kind == "photo" else VIDEO_MAX
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.geteuid()
            or st.st_nlink != 1
            or st.st_size > max_size
        ):
            raise PermissionError("refusing capture file")
        os.set_blocking(src_fd, True)
        parent = os.path.dirname(path)
        dirfd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        parent_st = os.fstat(dirfd)
        if not stat.S_ISDIR(parent_st.st_mode) or parent_st.st_uid != os.geteuid():
            raise PermissionError("untrusted capture directory")
        ext = "jpg" if kind == "photo" else "mp4"
        tmp_name = f".omasnapshot.{secrets.token_hex(8)}.{ext}"
        tmp_fd = os.open(
            tmp_name,
            os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
            dir_fd=dirfd,
        )
        os.fchmod(tmp_fd, 0o600)
        vf = f"eq=gamma={gamma:.2f}"
        cmd = [
            FFMPEG,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            f"/proc/self/fd/{src_fd}",
            "-vf",
            vf,
        ]
        if kind == "video":
            cmd += ["-c:a", "copy", "-fs", str(VIDEO_MAX), "-f", "mp4"]
        else:
            cmd += ["-q:v", "2", "-fs", str(PHOTO_MAX), "-f", "image2"]
        cmd.append(f"/proc/self/fd/{tmp_fd}")
        env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "HOME": pwd.getpwuid(os.geteuid()).pw_dir}
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        if runtime:
            env["XDG_RUNTIME_DIR"] = runtime
        p = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            start_new_session=True,
            env=env,
            pass_fds=(src_fd, tmp_fd),
            close_fds=True,
        )
        deadline = time.monotonic() + (PHOTO_DEADLINE if kind == "photo" else VIDEO_DEADLINE)
        err = b""
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    _kill_group(p.pid)
                    p.wait()
                    raise TimeoutError("gamma timed out")
                ready, _, _ = select.select([p.stderr], [], [], min(remaining, 0.2))
                if p.stderr in ready:
                    chunk = os.read(p.stderr.fileno(), 256)
                    if not chunk:
                        break
                    if len(err) <= ERR_MAX:
                        err += chunk[: ERR_MAX + 1 - len(err)]
                if p.poll() is not None:
                    rest = p.stderr.read(ERR_MAX + 1)
                    if rest and len(err) <= ERR_MAX:
                        err += rest[: ERR_MAX + 1 - len(err)]
                    break
            rc = p.wait()
            if rc != 0:
                raise RuntimeError("ffmpeg failed")
        finally:
            if p.stderr:
                p.stderr.close()
        os.fsync(tmp_fd)
        check_fd = os.open(tmp_name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dirfd)
        try:
            written = os.fstat(tmp_fd)
            named = os.fstat(check_fd)
            if (written.st_ino, written.st_dev) != (named.st_ino, named.st_dev):
                raise PermissionError("gamma temp was replaced")
            if written.st_size > max_size or written.st_size <= 0:
                raise PermissionError("gamma output rejected")
        finally:
            os.close(check_fd)
        os.rename(tmp_name, base, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        os.fsync(dirfd)
        tmp_name = None
    finally:
        if tmp_name is not None and dirfd is not None:
            try:
                os.unlink(tmp_name, dir_fd=dirfd)
            except OSError:
                pass
        if tmp_fd is not None:
            os.close(tmp_fd)
        if dirfd is not None:
            os.close(dirfd)
        os.close(src_fd)


def main(argv):
    if len(argv) < 2:
        return 2
    op = argv[1]
    try:
        if op == "read-settings":
            cmd_read_settings()
            return 0
        if op == "write-settings":
            if len(argv) != 3:
                return 2
            cmd_write_settings(argv[2])
            return 0
        if op == "xdg-dirs":
            cmd_xdg_dirs()
            return 0
        if op == "gamma":
            if len(argv) != 5:
                return 2
            cmd_gamma(argv[2], argv[3], argv[4])
            return 0
        return 2
    except BrokenPipeError:
        return 1
    except (ValueError, PermissionError, FileNotFoundError, TimeoutError, RuntimeError, json.JSONDecodeError, OSError):
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
