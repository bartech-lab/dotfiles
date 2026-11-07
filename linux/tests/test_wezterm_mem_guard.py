"""Behavior tests for wezterm-mem-guard. Run: python3 -m unittest linux/tests/test_wezterm_mem_guard.py"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

GUARD = Path(__file__).resolve().parents[1] / "bin" / "wezterm-mem-guard"
GIB = 1 << 30
HIGH = 32 * GIB
UNIT = "app-org.wezfurlong.wezterm@abc.service"


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.tmp)])
        self.home = self.tmp / "home"
        (self.home / ".local/bin").mkdir(parents=True)
        self.notes = self.tmp / "notes"
        ops = self.home / ".local/bin/ops"
        ops.write_text(f'#!/bin/sh\nprintf "%s|" "$@" >> {self.notes}\necho >> {self.notes}\n')
        ops.chmod(0o755)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.cg = self.tmp / "cg" / UNIT
        self.cg.mkdir(parents=True)
        self.procs = []

    def spawn(self, name, *args, mib=1, subgroup=None):
        exe = self.bin / name
        if not exe.exists():
            exe.symlink_to(os.path.realpath(sys.executable))
        code = f"import sys,time; a=b'x'*({mib}<<20); sys.stdout.write('r'); sys.stdout.flush(); time.sleep(60)"
        p = subprocess.Popen([str(exe), "-c", code, *args], stdout=subprocess.PIPE)
        self.addCleanup(p.stdout.close)
        self.addCleanup(p.wait)
        self.addCleanup(p.kill)
        self.assertEqual(p.stdout.read(1), b"r")
        self.procs.append((p.pid, subgroup))
        return p

    def write_cgroup(self, anon, high=HIGH):
        groups = {}
        for pid, sub in self.procs:
            groups.setdefault(sub, []).append(str(pid))
        for sub, pids in groups.items():
            d = self.cg / sub if sub else self.cg
            d.mkdir(exist_ok=True)
            (d / "cgroup.procs").write_text("\n".join(pids) + "\n")
        (self.cg / "memory.high").write_text(("max" if high is None else str(high)) + "\n")
        (self.cg / "memory.stat").write_text(f"file 123\nanon {anon}\nshmem 0\n")

    def run_once(self):
        env = {**os.environ, "HOME": str(self.home), "WEZTERM_MEM_GUARD_ROOT": str(self.tmp / "cg")}
        out = subprocess.run([str(GUARD), "--once"], env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout

    def alive(self, p):
        time.sleep(0.2)
        return p.poll() is None

    def test_below_warn_kills_nothing(self):
        browser = self.spawn("chromium", "--headless=new")
        self.write_cgroup(HIGH * 75 // 100 - 1)
        self.assertTrue(self.run_once().startswith("ok"))
        self.assertTrue(self.alive(browser))
        self.assertFalse(self.notes.exists())

    def test_between_warn_and_act_warns_without_killing(self):
        browser = self.spawn("chromium", "--headless=new")
        self.write_cgroup(HIGH * 90 // 100 - 1)
        self.assertTrue(self.run_once().startswith("warn"))
        self.assertTrue(self.alive(browser))

    def test_at_act_kills_only_headless_chromium(self):
        headless = [self.spawn("chromium", "--headless=new"), self.spawn("chrome-headless-shell", "--headless")]
        nested = self.spawn("chromium", "--headless", subgroup="tab")
        windowed = self.spawn("chromium", "--remote-debugging-port=9222")
        big_job = self.spawn("cc1plus", mib=64)
        self.write_cgroup(HIGH * 90 // 100 + 1)
        out = self.run_once()
        self.assertIn("Killed 3 headless Chromium", out)
        for p in headless + [nested]:
            self.assertFalse(self.alive(p))
        self.assertTrue(self.alive(windowed))
        self.assertTrue(self.alive(big_job))
        self.assertIn("WezTerm memory guard acted", self.notes.read_text())

    def spawn_tree(self, argv0, child_argv0):
        """A parent whose cmdline is one space-joined string, as Chromium rewrites it, with one child."""
        exe = self.bin / "chromium"
        if not exe.exists():
            exe.symlink_to(os.path.realpath(sys.executable))
        code = ("import subprocess,sys,time; c=subprocess.Popen([%r,'-c','import time; a=bytearray(8<<20); time.sleep(60)'],"
                "executable=%r); print(c.pid, flush=True); time.sleep(60)") % (child_argv0, os.path.realpath(sys.executable))
        p = subprocess.Popen([argv0, "-c", code], executable=str(exe), stdout=subprocess.PIPE, text=True)
        child = int(p.stdout.readline())
        self.addCleanup(p.stdout.close)
        self.addCleanup(p.wait)
        self.addCleanup(p.kill)
        self.addCleanup(lambda: subprocess.run(["kill", "-9", str(child)], stderr=subprocess.DEVNULL))
        self.procs += [(p.pid, None), (child, None)]
        return p, child

    def child_alive(self, pid):
        time.sleep(0.2)
        try:
            return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
        except OSError:
            return False

    def test_rewritten_cmdline_and_renderer_children_are_killed(self):
        zygote, renderer = self.spawn_tree("chromium --type=zygote --headless=new", "chromium --type=renderer")
        window, window_renderer = self.spawn_tree("chromium --type=zygote", "chromium --type=renderer")
        self.write_cgroup(HIGH)
        self.assertIn("Killed 2 headless Chromium", self.run_once())
        self.assertFalse(self.alive(zygote))
        self.assertFalse(self.child_alive(renderer))
        self.assertTrue(self.alive(window))
        self.assertTrue(self.child_alive(window_renderer))

    def test_without_browsers_kills_nothing_and_names_largest_unprotected(self):
        claude = self.spawn("claude", mib=128)
        shell = self.spawn("zsh", mib=96)
        small = self.spawn("pytest", mib=8)
        large = self.spawn("node", mib=48)
        self.write_cgroup(int(0.95 * HIGH))
        out = self.run_once()
        self.assertTrue(out.startswith("critical"), out)
        self.assertIn(f"kill {large.pid}", out)
        for p in (claude, shell, small, large):
            self.assertTrue(self.alive(p))
        self.assertIn("nothing killed", self.notes.read_text())

    def test_only_protected_processes_kills_nothing(self):
        claude = self.spawn("claude", mib=64)
        self.write_cgroup(int(0.99 * HIGH))
        self.assertIn("Nothing was killed", self.run_once())
        self.assertTrue(self.alive(claude))

    def test_unit_inside_app_sub_slice_is_guarded(self):
        self.cg = self.tmp / "cg" / "app-app\\x2dorg.wezfurlong.wezterm.slice" / UNIT
        self.cg.mkdir(parents=True)
        browser = self.spawn("chromium", "--headless")
        self.write_cgroup(HIGH)
        self.assertIn("Killed 1 headless Chromium", self.run_once())
        self.assertFalse(self.alive(browser))

    def test_loop_alerts_once_per_episode_and_again_after_recovery(self):
        self.write_cgroup(0)
        env = {**os.environ, "HOME": str(self.home), "WEZTERM_MEM_GUARD_ROOT": str(self.tmp / "cg")}
        steps = [(85, "warn"), (85, None), (80, None), (95, "critical"), (95, None), (85, None),
                 (10, None), (85, "warn")]
        guard = subprocess.Popen([str(GUARD), "--ticks", str(len(steps))], env=env, text=True,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(guard.kill)
        self.addCleanup(guard.stdout.close)
        self.addCleanup(guard.stdin.close)
        self.addCleanup(guard.stderr.close)
        seen = []
        for i, (percent, expected) in enumerate(steps):
            self.write_cgroup(HIGH * percent // 100)
            if i:
                guard.stdin.write("\n")
                guard.stdin.flush()
            self.assertEqual(guard.stdout.readline(), "tick\n", guard.stderr.read() if guard.poll() is not None else "")
            notes = self.notes.read_text().splitlines() if self.notes.exists() else []
            new, seen = notes[len(seen):], notes
            if expected is None:
                self.assertEqual(new, [], f"step {i} at {percent}%")
            else:
                self.assertEqual(len(new), 1, f"step {i} at {percent}%")
                self.assertIn("is critical" if expected == "critical" else "is high", new[0])
        guard.stdin.write("\n")
        guard.stdin.flush()
        self.assertEqual(guard.wait(timeout=10), 0)

    def test_no_memory_high_is_ignored(self):
        browser = self.spawn("chromium", "--headless")
        self.write_cgroup(100 * GIB, high=None)
        self.assertTrue(self.run_once().startswith("ok"))
        self.assertTrue(self.alive(browser))


if __name__ == "__main__":
    unittest.main()
