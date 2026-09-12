#!/usr/bin/python3 -I
import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, rel):
    path = ROOT / rel
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


helper = load("omasnapshot", "bin/omasnapshot.py")
desktop = load("edit_desktop", "bin/edit-desktop.py")


class SettingsTests(unittest.TestCase):
    def test_write_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = tmp
            victim = Path(tmp) / "victim"
            victim.write_text("must survive\n")
            dirfd = helper.settings_dirfd(home=home)
            try:
                os.symlink(str(victim), "settings.json", dir_fd=dirfd)
            finally:
                os.close(dirfd)
            helper.cmd_write_settings("1.50", home=home)
            self.assertEqual(victim.read_text(), "must survive\n")
            dirfd = helper.settings_dirfd(home=home)
            try:
                raw = helper.read_bounded(dirfd, "settings.json")
            finally:
                os.close(dirfd)
            self.assertEqual(json.loads(raw)["gamma"], 1.5)

    def test_read_refuses_world_writable_and_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            dirfd = helper.settings_dirfd(home=tmp)
            try:
                helper.write_atomic(dirfd, "settings.json", helper.settings_payload(1))
                os.chmod("settings.json", 0o644, dir_fd=dirfd)
                with self.assertRaises(PermissionError):
                    helper.read_bounded(dirfd, "settings.json")
                os.unlink("settings.json", dir_fd=dirfd)
                os.symlink("/etc/passwd", "settings.json", dir_fd=dirfd)
                with self.assertRaises(OSError):
                    helper.read_bounded(dirfd, "settings.json")
            finally:
                os.close(dirfd)

    def test_read_refuses_fifo(self):
        with tempfile.TemporaryDirectory() as tmp:
            dirfd = helper.settings_dirfd(home=tmp)
            try:
                os.mkfifo("settings.json", 0o600, dir_fd=dirfd)
                with self.assertRaises(PermissionError):
                    helper.read_bounded(dirfd, "settings.json")
            finally:
                os.close(dirfd)

    def test_roundtrip_and_clamp(self):
        with tempfile.TemporaryDirectory() as tmp:
            helper.cmd_write_settings("1.54", home=tmp)
            dirfd = helper.settings_dirfd(home=tmp)
            try:
                raw = helper.read_bounded(dirfd, "settings.json")
                st = os.stat("settings.json", dir_fd=dirfd, follow_symlinks=False)
            finally:
                os.close(dirfd)
            self.assertEqual(helper.parse_settings(raw), 1.55)
            self.assertEqual(stat.S_IMODE(st.st_mode), 0o600)

    def test_usable_paths_and_gamma_parse(self):
        self.assertTrue(helper.usable_abs_path("/home/colin/Pictures/x.jpg"))
        self.assertFalse(helper.usable_abs_path("/home/colin/../etc/passwd"))
        self.assertEqual(helper.parse_gamma("1.5"), 1.5)
        with self.assertRaises(ValueError):
            helper.parse_gamma("1.5;id")
        with self.assertRaises(ValueError):
            helper.parse_gamma("eq=gamma=1")


class GammaTests(unittest.TestCase):
    def test_refuses_symlink_capture(self):
        with tempfile.TemporaryDirectory() as tmp:
            victim = Path(tmp) / "victim"
            victim.write_text("must survive\n")
            dest = Path(tmp) / "omasnapshot-test.jpg"
            dest.symlink_to(victim)
            with self.assertRaises(OSError):
                helper.cmd_gamma("photo", str(dest), "1.50")
            self.assertEqual(victim.read_text(), "must survive\n")

    def test_applies_gamma_when_ffmpeg_exists(self):
        if not os.path.isfile("/usr/bin/ffmpeg"):
            self.skipTest("ffmpeg missing")
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "omasnapshot-src.jpg"
            created = subprocess.run(
                [
                    "/usr/bin/ffmpeg",
                    "-y",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=black:s=16x16:d=0.1",
                    "-frames:v",
                    "1",
                    str(src),
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if created.returncode != 0 or not src.is_file():
                self.skipTest("could not create jpeg")
            helper.cmd_gamma("photo", str(src), "1.50")
            self.assertTrue(src.is_file())
            self.assertGreater(src.stat().st_size, 0)
            self.assertFalse(src.is_symlink())


class DesktopTests(unittest.TestCase):
    def test_add_remove_and_symlink_safe(self):
        with tempfile.TemporaryDirectory() as tmp:
            hypr = Path(tmp) / "hypr"
            ext = Path(tmp) / "omarchy" / "extensions"
            hypr.mkdir()
            bind = hypr / "bindings.lua"
            menu = ext / "omarchy-menu.jsonc"
            bind.write_text("o.bind('x', 'y', 'z')\n")
            os.chmod(bind, 0o644)
            plugin = "io.github.cfaulkingham.omasnapshot"
            desktop.apply(str(bind), str(menu), "add", "SUPER + ALT + C", plugin, reload_hypr=False)
            bind_text = bind.read_text()
            menu_text = menu.read_text()
            self.assertIn("omasnapshot (install.sh)", bind_text)
            self.assertIn("trigger.capture.camera", menu_text)
            self.assertEqual(stat.S_IMODE(menu.stat().st_mode), 0o644)
            desktop.apply(str(bind), str(menu), "remove", "SUPER + ALT + C", plugin, reload_hypr=False)
            self.assertNotIn("omasnapshot (install.sh)", bind.read_text())
            self.assertNotIn("trigger.capture.camera", menu.read_text())

    def test_write_replaces_symlink_without_clobbering_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            victim = Path(tmp) / "victim"
            victim.write_text("must survive\n")
            dest = Path(tmp) / "bindings.lua"
            dest.symlink_to(victim)
            with self.assertRaises(SystemExit):
                desktop.read_file(str(dest))
            desktop.atomic_write(str(dest), "new\n", 0o644)
            self.assertEqual(victim.read_text(), "must survive\n")
            self.assertTrue(dest.is_file())
            self.assertFalse(dest.is_symlink())
            self.assertEqual(dest.read_text(), "new\n")

    def test_malformed_markers_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            bind = Path(tmp) / "bindings.lua"
            menu = Path(tmp) / "omarchy-menu.jsonc"
            bind.write_text("-- omasnapshot (install.sh)\nnot a bind\n")
            menu.write_text("{}\n")
            with self.assertRaises(SystemExit):
                desktop.apply(
                    str(bind),
                    str(menu),
                    "add",
                    "SUPER + ALT + C",
                    "io.github.cfaulkingham.omasnapshot",
                    reload_hypr=False,
                )
            self.assertEqual(bind.read_text(), "-- omasnapshot (install.sh)\nnot a bind\n")


if __name__ == "__main__":
    unittest.main()
