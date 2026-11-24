"""Behavior tests for the comfyui launcher with fake gaming and systemd-run. Run: python3 -m unittest linux/tests/test_comfyui.py"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "comfyui"
FAKE_GAMING = """#!/bin/bash
echo "gaming $*" >> "$CALLS"
if [ "$1" = status ]; then
    if [ -f "$STATE" ]; then
        echo "Game mode on since 2026-11-24 10:00. VRAM free: 12.0 GB"
        sleep 0.3
        for i in $(seq 1 3000); do echo "  stopped: unit-$i.service"; done
    else
        echo "Game mode off. VRAM free: 2.0 GB"
    fi
elif [ "$1" = on ]; then
    touch "$STATE"
elif [ "$1" = off ]; then
    rm -f "$STATE"
fi
"""
FAKE_SYSTEMD_RUN = """#!/bin/bash
echo "systemd-run $*" >> "$CALLS"
exit "${RUN_EXIT:-0}"
"""


class ComfyuiLauncherTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        (root / "home" / "Projects" / "faceswap" / "ComfyUI").mkdir(parents=True)
        self.bin = root / "bin"
        self.bin.mkdir()
        for name, body in (("gaming", FAKE_GAMING), ("systemd-run", FAKE_SYSTEMD_RUN)):
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        self.calls = root / "calls"
        self.state = root / "game-mode-on"
        self.env = {"HOME": str(root / "home"), "PATH": f"{self.bin}:/usr/bin:/bin",
                    "CALLS": str(self.calls), "STATE": str(self.state)}

    def run_launcher(self, run_exit=0):
        env = dict(self.env, RUN_EXIT=str(run_exit))
        result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True, timeout=30)
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        return result, calls

    def test_game_mode_that_was_already_on_is_left_on_even_when_status_prints_many_lines(self):
        self.state.touch()
        for _ in range(3):
            result, calls = self.run_launcher()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("gaming on", calls)
            self.assertNotIn("gaming off", calls)
            self.assertTrue(self.state.exists())

    def test_game_mode_that_the_launcher_turned_on_is_turned_off_after_the_run(self):
        result, calls = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c.split(" --")[0] for c in calls], ["gaming status", "gaming on", "systemd-run", "gaming off"])
        self.assertFalse(self.state.exists())

    def test_a_failed_run_keeps_its_exit_code_and_still_turns_game_mode_off(self):
        result, calls = self.run_launcher(run_exit=137)
        self.assertEqual(result.returncode, 137)
        self.assertEqual(calls[-1], "gaming off")

    def test_a_run_stopped_with_ctrl_c_counts_as_a_clean_exit(self):
        result, _ = self.run_launcher(run_exit=130)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
