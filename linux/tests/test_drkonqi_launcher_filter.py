"""Behavior tests for drkonqi-launcher-filter. Run: python3 -m unittest linux/tests/test_drkonqi_launcher_filter.py"""

import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

FILTER = Path(__file__).resolve().parents[1] / "bin" / "drkonqi-launcher-filter"
HEADLESS = ("/home/u/.cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/"
            "chrome-headless-shell --type=renderer --enable-automation")
DOCKER_CHROMIUM = "/ms-playwright/chromium-1248/chrome-linux64/chrome --type=renderer"


def record(cmdline=None, **extra):
    fields = {"COREDUMP_COMM": "x", "COREDUMP_SIGNAL": "11", **extra}
    if cmdline is not None:
        fields["COREDUMP_CMDLINE"] = cmdline
    return json.dumps(dict(sorted(fields.items()))).encode()


class FilterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.tmp)])
        self.home = self.tmp / "home"
        (self.home / ".local/bin").mkdir(parents=True)
        self.notes = self.tmp / "notes"
        ops = self.home / ".local/bin/ops"
        ops.write_text(f'#!/bin/sh\nprintf "%s|" "$@" >> {self.notes}\necho >> {self.notes}\n')
        ops.chmod(0o755)
        self.launched = self.tmp / "launched.json"
        self.launcher = self.tmp / "drkonqi-coredump-launcher"
        self.launcher.write_text(
            f"#!{sys.executable}\nimport json, os, socket, sys\n"
            "s = socket.socket(fileno=3)\n"
            f"json.dump({{'argv': sys.argv[1:], 'data': s.recv(1 << 16).decode()}}, open({str(self.launched)!r}, 'w'))\n")
        self.launcher.chmod(0o755)
        self.unit = self.tmp / "drkonqi-coredump-launcher@.service"
        self.set_vendor_exec(f"ExecStart={self.launcher}")

    def set_vendor_exec(self, *lines):
        self.unit.write_text("[Unit]\nDescription=x\n\n[Service]\n" + "\n".join(lines) + "\n")

    def run_filter(self, data, launcher=None, listen_fds="1", args=()):
        src = FILTER.read_text()
        for name, value in (("LAUNCHER", launcher or self.launcher), ("VENDOR_UNIT", self.unit)):
            lines = [l for l in src.splitlines() if l.startswith(f"{name} = ")]
            self.assertEqual(len(lines), 1, f"{name} constant not found in the filter")
            src = src.replace(lines[0], f"{name} = {str(value)!r}")
        script = self.tmp / "filter.py"
        script.write_text(src)
        a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        a.send(data)
        env = {"HOME": str(self.home), "PATH": os.environ["PATH"]}
        if listen_fds is not None:
            env["LISTEN_FDS"] = listen_fds
        proc = subprocess.run(["sh", "-c", 'exec 3<&"$0"; exec "$@"', str(b.fileno()), sys.executable, "-I",
                               str(script), *args], env=env, capture_output=True, text=True, timeout=30,
                              pass_fds=(b.fileno(),))
        a.close(), b.close()
        return proc

    def launched_with(self):
        return json.loads(self.launched.read_text()) if self.launched.exists() else None

    def notifications(self):
        return self.notes.read_text().splitlines() if self.notes.exists() else []

    def assert_dropped(self, cmdline):
        proc = self.run_filter(record(cmdline))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIsNone(self.launched_with(), "a Playwright crash reached DrKonqi")
        self.assertEqual(self.notifications(), [])

    def assert_passed_unchanged(self, data, notified):
        proc = self.run_filter(data, args=("--extra",))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        got = self.launched_with()
        self.assertIsNotNone(got, f"crash did not reach DrKonqi: {proc.stderr}")
        self.assertEqual(got["data"], data.decode(), "the record was consumed or changed before DrKonqi read it")
        self.assertEqual(got["argv"], ["--extra"])
        self.assertEqual(len(self.notifications()), 1 if notified else 0, self.notifications())

    def test_headless_shell_crash_is_dropped(self):
        self.assert_dropped(HEADLESS)

    def test_full_chromium_in_the_container_is_dropped(self):
        self.assert_dropped(DOCKER_CHROMIUM)

    def test_systemd_quoted_cmdline_is_dropped(self):
        self.assert_dropped("$'" + HEADLESS + "\\x01'")

    def test_other_app_reaches_drkonqi_with_the_record_intact(self):
        self.assert_passed_unchanged(record("/usr/bin/dolphin --new-window"), notified=False)

    def test_playwright_path_as_an_argument_is_not_dropped(self):
        self.assert_passed_unchanged(record("/usr/bin/node /home/b/.cache/ms-playwright/chromium-1248/x"),
                                     notified=False)

    def test_other_ms_playwright_browser_is_not_dropped(self):
        self.assert_passed_unchanged(record("/home/b/.cache/ms-playwright/firefox-1490/firefox/firefox"),
                                     notified=False)

    def test_missing_cmdline_passes_and_alerts(self):
        self.assert_passed_unchanged(record(None, COREDUMP_EXE="/usr/bin/dolphin"), notified=True)

    def test_missing_listen_fds_passes_and_alerts(self):
        proc = self.run_filter(record(HEADLESS), listen_fds=None)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIsNotNone(self.launched_with(), "without LISTEN_FDS the crash must still reach DrKonqi")
        self.assertEqual(len(self.notifications()), 1)

    def test_changed_vendor_exec_start_alerts_but_still_filters(self):
        self.set_vendor_exec(f"ExecStart={self.launcher} --new-flag")
        proc = self.run_filter(record(HEADLESS))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIsNone(self.launched_with())
        self.assertEqual(len(self.notifications()), 1)
        self.assertIn("--new-flag", self.notifications()[0])

    def test_second_vendor_exec_start_alerts(self):
        self.set_vendor_exec(f"ExecStart={self.launcher}", "ExecStartPost=/bin/true", f"ExecStart={self.launcher}")
        self.run_filter(record("/usr/bin/dolphin"))
        self.assertEqual(len(self.notifications()), 1)

    def test_missing_launcher_fails_and_alerts(self):
        missing = self.tmp / "gone"
        self.set_vendor_exec(f"ExecStart={missing}")
        proc = self.run_filter(record("/usr/bin/dolphin"), launcher=missing)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(len(self.notifications()), 1)
        self.assertIn("cannot run", self.notifications()[0])

    def test_alerts_at_most_once_a_day(self):
        self.run_filter(record(None))
        self.run_filter(record(None))
        self.assertEqual(len(self.notifications()), 1)
        stamp = self.home / ".local/state/drkonqi-launcher-filter.alerted"
        old = time.time() - 86400 - 60
        os.utime(stamp, (old, old))
        self.run_filter(record(None))
        self.assertEqual(len(self.notifications()), 2)

    def test_failing_ops_does_not_block_drkonqi(self):
        (self.home / ".local/bin/ops").unlink()
        self.assert_passed_unchanged(record(None), notified=False)


if __name__ == "__main__":
    unittest.main()
