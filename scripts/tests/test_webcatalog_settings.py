#!/usr/bin/env python3
"""webcatalog-settings.py sets the tracked keys in every user's settings.json, keeps the rest, skips missing apps."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "webcatalog-settings.py")


class WebCatalogSettings(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = os.path.join(tmp.name, "WebCatalog")
        self.config = os.path.join(tmp.name, "config")
        os.makedirs(self.config)
        self.track("global", {"spellcheck": False})
        self.track("protonmail", {"tabBarVisibility": "when_multiple_tabs", "toolbar": False})

    def track(self, name, keys):
        with open(os.path.join(self.config, name + ".json"), "w") as f:
            json.dump(keys, f)

    def settings(self, rel, data):
        path = os.path.join(self.base, rel, "settings.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f)
        return path

    def load(self, path):
        with open(path) as f:
            return json.load(f)

    def run_script(self, *extra):
        return subprocess.run([sys.executable, SCRIPT, "--webcatalog-dir", self.base, "--config-dir", self.config, *extra],
                              capture_output=True, text=True)

    def test_sets_tracked_keys_and_keeps_others_for_every_user(self):
        a = self.settings("photon/protonmail/users/u1", {"settings": {"toolbar": True, "subspaceBar": True}, "lastUserModifiedAt": 5})
        b = self.settings("photon/protonmail/users/u2", {"settings": {}})
        g = self.settings("users/u1", {"settings": {"spellcheck": True, "searchEngine": "brave"}})
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.load(a), {"settings": {"toolbar": False, "subspaceBar": True, "tabBarVisibility": "when_multiple_tabs"},
                                        "lastUserModifiedAt": 5})
        self.assertEqual(self.load(b)["settings"], {"tabBarVisibility": "when_multiple_tabs", "toolbar": False})
        self.assertEqual(self.load(g)["settings"], {"spellcheck": False, "searchEngine": "brave"})

    def test_global_settings_do_not_leak_into_app_settings(self):
        a = self.settings("photon/protonmail/users/u1", {"settings": {}})
        self.run_script()
        self.assertNotIn("spellcheck", self.load(a)["settings"])

    def test_dry_run_writes_nothing(self):
        a = self.settings("photon/protonmail/users/u1", {"settings": {"toolbar": True}})
        before = open(a).read()
        r = self.run_script("--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(open(a).read(), before)
        self.assertIn("toolbar", r.stdout)

    def test_app_not_installed_is_skipped_not_created(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.base, "photon")))
        self.assertIn("protonmail", r.stdout)

    def test_unchanged_file_is_not_rewritten(self):
        a = self.settings("photon/protonmail/users/u1", {"settings": {"tabBarVisibility": "when_multiple_tabs", "toolbar": False}})
        os.utime(a, (1, 1))
        self.run_script()
        self.assertEqual(os.stat(a).st_mtime, 1)


if __name__ == "__main__":
    unittest.main()
