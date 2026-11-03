"""Behavior tests for cpu-uv-check with a fake journalctl. Run: python3 -m unittest linux/tests/test_cpu_uv_check.py"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "cpu-uv-check"
FAKE_JOURNALCTL = """#!/bin/bash
d="$FAKE_JD"
case "$1" in
  --list-boots)
    [ "$*" = "--list-boots --no-pager -q" ] || { echo "unexpected: $*" >&2; exit 2; }
    cat "$d/list-boots.txt" ;;
  -k)
    if [ "$*" = "-k --no-pager -q" ]; then
      cat "$d/kernel-all.txt"
    elif [ "$2" = "-b" ] && [ "$*" = "-k -b $3 --no-pager -q" ]; then
      cat "$d/kernel-$3.txt"
    else
      echo "unexpected: $*" >&2; exit 2
    fi ;;
  -b)
    if [ "$*" = "-b $2 --no-pager -q -n 300" ]; then
      cat "$d/tail-$2.txt"
    else
      echo "unexpected: $*" >&2; exit 2
    fi ;;
  *) echo "unexpected: $*" >&2; exit 2 ;;
esac
"""
CLEAN = "systemd[1]: Shutting down.\\nreboot: Power down\\n".replace("\\n", "\n")
UNCLEAN = "systemd[1]: Started something.\nkernel: usb 1-1: new device\n"
MCE_A = "kernel: mce: [Hardware Error]: CPU 3: Machine Check: 0 Bank 1"
MCE_B = "kernel: 2 Machine Check Events Logged"
MCE_C = "kernel: MCE: [HARDWARE ERROR]: old boot error"


class CpuUvCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        (base / "bin").mkdir()
        fake = base / "bin" / "journalctl"
        fake.write_text(FAKE_JOURNALCTL)
        fake.chmod(0o755)
        self.data = base / "data"
        self.data.mkdir()
        self.path = f"{base / 'bin'}:{os.environ['PATH']}"

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, count, kernel=None, tail=None, kernel_all="", args=()):
        kernel = kernel or {}
        tail = tail or {}
        lines = []
        for n, idx in enumerate(count):
            lines.append(
                f"{idx:>3} {n:032x} Mon 2026-11-0{n + 1} 08:00:00 CET Mon 2026-11-0{n + 1} 20:00:00 CET"
            )
            (self.data / f"kernel-{idx}.txt").write_text(kernel.get(idx, "kernel: all quiet\n"))
            (self.data / f"tail-{idx}.txt").write_text(tail.get(idx, CLEAN))
        (self.data / "list-boots.txt").write_text("\n".join(lines) + "\n")
        (self.data / "kernel-all.txt").write_text(kernel_all)
        env = {**os.environ, "PATH": self.path, "FAKE_JD": str(self.data)}
        return subprocess.run([str(SCRIPT), *args], env=env, capture_output=True, text=True)

    @staticmethod
    def boot_line(result, idx):
        found = [l for l in result.stdout.splitlines() if l.split()[:2] == ["boot", str(idx)]]
        assert len(found) == 1, result.stdout
        return found[0]

    def test_all_clean_exits_zero(self):
        r = self.run_script([-2, -1, 0])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        for idx in (-2, -1):
            line = self.boot_line(r, idx)
            self.assertIn("clean-shutdown=yes", line)
            self.assertIn("mce=0", line)
            self.assertNotIn("<-- check", line)
        zero = self.boot_line(r, 0)
        self.assertIn("clean-shutdown=(running)", zero)
        self.assertNotIn("<-- check", zero)
        self.assertIn("latest MCE lines (all boots)", r.stdout)
        self.assertIn("(none)", r.stdout)

    def test_middle_boot_without_clean_marker_exits_one(self):
        r = self.run_script([-2, -1, 0], tail={-1: UNCLEAN})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        bad = self.boot_line(r, -1)
        self.assertIn("clean-shutdown=NO", bad)
        self.assertIn("<-- check", bad)
        for idx in (-2, 0):
            self.assertNotIn("<-- check", self.boot_line(r, idx))
        self.assertIn("clean-shutdown=yes", self.boot_line(r, -2))

    def test_mce_lines_are_counted_and_exit_one(self):
        kernel = {-1: f"kernel: ok\n{MCE_A}\n{MCE_B}\nkernel: unrelated\n"}
        r = self.run_script([-1, 0], kernel=kernel, kernel_all=f"{MCE_A}\n{MCE_B}\n")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        line = self.boot_line(r, -1)
        self.assertIn("mce=2", line)
        self.assertIn("<-- check", line)
        self.assertIn("mce=0", self.boot_line(r, 0))

    def test_mce_outside_window_is_listed_but_does_not_fail(self):
        r = self.run_script(
            [-4, -3, -2, -1, 0],
            kernel={-4: f"{MCE_C}\n"},
            kernel_all=f"{MCE_C}\nkernel: noise\n",
            args=["2"],
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn(MCE_C, r.stdout)
        self.assertNotIn("(none)", r.stdout)

    def test_argument_limits_boot_count(self):
        r = self.run_script([-4, -3, -2, -1, 0], args=["2"])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        boot_lines = [l for l in r.stdout.splitlines() if l.startswith("boot ")]
        self.assertEqual(len(boot_lines), 2, r.stdout)
        self.assertEqual(boot_lines[0].split()[:2], ["boot", "-1"])
        self.assertEqual(boot_lines[1].split()[:2], ["boot", "0"])

    def test_only_last_eight_mce_lines_are_printed(self):
        lines = [f"kernel: mce: [Hardware Error]: number {n:02d}" for n in range(12)]
        r = self.run_script([-1, 0], kernel_all="\n".join(lines) + "\n")
        for n in range(4):
            self.assertNotIn(f"number {n:02d}", r.stdout)
        for n in range(4, 12):
            self.assertIn(f"number {n:02d}", r.stdout)

    def test_each_clean_marker_is_accepted(self):
        for marker in (
            "reboot: Power down",
            "reboot: Restarting system",
            "Journal stopped",
            "Reached target System Power Off",
            "Reached target System Reboot",
        ):
            with self.subTest(marker=marker):
                r = self.run_script([-1, 0], tail={-1: f"kernel: x\n{marker}\n"})
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn("clean-shutdown=yes", self.boot_line(r, -1))


if __name__ == "__main__":
    unittest.main()
