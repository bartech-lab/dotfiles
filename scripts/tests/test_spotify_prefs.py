#!/usr/bin/env python3
"""spotify-prefs.py sets the tracked keys in every user's prefs, keeps the rest, never writes while Spotify runs."""
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "spotify-prefs.py")
TRACKED = os.path.join(os.path.dirname(SCRIPT), "..", "config", "spotify", "user-prefs")


class SpotifyPrefs(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = tmp.name
        self.base = os.path.join(self.root, "spotify")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        self.pgrep(running=False)
        self.tracked = os.path.join(self.root, "tracked")
        with open(self.tracked, "w") as f:
            f.write("# comment\naudio.automix=false\nui.hide_hpto=true\n")

    def pgrep(self, running):
        path = os.path.join(self.bin, "pgrep")
        with open(path, "w") as f:
            f.write(f"#!/bin/sh\nexit {0 if running else 1}\n")
        os.chmod(path, 0o755)
        subprocess.run([path])  # macOS scans a new executable on its first run

    def user(self, name, text):
        d = os.path.join(self.base, "Users", f"{name}-user")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "prefs"), "w") as f:
            f.write(text)
        return os.path.join(d, "prefs")

    def run_script(self, *extra, tracked=None):
        env = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"])
        return subprocess.run([sys.executable, SCRIPT, *extra, "--spotify-dir", self.base, tracked or self.tracked],
                              capture_output=True, text=True, env=env)

    def test_sets_keys_in_every_user_and_keeps_the_rest(self):
        a = self.user("a", 'connect.dial_devices="[]"\naudio.automix=true\n')
        b = self.user("b", "")
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(open(a).read().splitlines(), ['connect.dial_devices="[]"', "audio.automix=false", "ui.hide_hpto=true"])
        self.assertEqual(open(b).read().splitlines(), ["audio.automix=false", "ui.hide_hpto=true"])

    def test_running_spotify_blocks_the_write(self):
        a = self.user("a", "audio.automix=true\n")
        self.pgrep(running=True)
        r = self.run_script()
        self.assertEqual(r.returncode, 1)
        self.assertEqual(open(a).read(), "audio.automix=true\n")

    def test_dry_run_writes_nothing_even_while_spotify_runs(self):
        a = self.user("a", "audio.automix=true\n")
        self.pgrep(running=True)
        r = self.run_script("--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("audio.automix", r.stdout)
        self.assertEqual(open(a).read(), "audio.automix=true\n")

    def test_no_signed_in_user_is_a_skip(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("no signed-in user", r.stdout)

    def test_tracked_file_parses(self):
        self.user("a", "")
        r = self.run_script(tracked=TRACKED)
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
