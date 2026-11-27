#!/usr/bin/env python3
"""browser-prefs.py merges tracked values into the browser's files and never writes while it is open."""
import json
import os
import platform
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "browser-prefs.py")
CONFIG = os.path.join(os.path.dirname(SCRIPT), "..", "config")


class BravePrefs(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = tmp.name
        self.udd = os.path.join(self.root, "udd")
        os.makedirs(os.path.join(self.udd, "Default"))
        self.src = os.path.join(self.root, "tracked.json")

    def run_script(self, tracked, *extra):
        with open(self.src, "w") as f:
            json.dump(tracked, f)
        return subprocess.run([sys.executable, SCRIPT, "brave", *extra, "--user-data-dir", self.udd, self.src],
                              capture_output=True, text=True)

    def prefs(self, name="Default/Preferences"):
        with open(os.path.join(self.udd, name)) as f:
            return json.load(f)

    def write_prefs(self, data, name="Default/Preferences"):
        with open(os.path.join(self.udd, name), "w") as f:
            json.dump(data, f)

    def test_merge_sets_leaves_and_keeps_every_other_setting(self):
        self.write_prefs({"brave": {"new_tab_page": {"show_stats": True, "other": 1}, "kept": "x"},
                          "translate": "not a dict", "extensions": {"settings": {"id": {}}}})
        r = self.run_script({"Default/Preferences": {"brave": {"new_tab_page": {"show_stats": False}},
                                                     "translate": {"enabled": False}}})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.prefs(), {"brave": {"new_tab_page": {"show_stats": False, "other": 1}, "kept": "x"},
                                        "translate": {"enabled": False}, "extensions": {"settings": {"id": {}}}})

    def test_a_missing_file_is_created(self):
        r = self.run_script({"Local State": {"brave": {"p3a": {"enabled": False}}}})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.prefs("Local State"), {"brave": {"p3a": {"enabled": False}}})

    def test_open_brave_blocks_every_write(self):
        os.symlink(f"{platform.node()}-{os.getpid()}", os.path.join(self.udd, "SingletonLock"))
        self.write_prefs({"a": 1})
        r = self.run_script({"Default/Preferences": {"a": 2}, "Local State": {"b": 1}})
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.prefs(), {"a": 1})
        self.assertFalse(os.path.exists(os.path.join(self.udd, "Local State")))

    def test_a_stale_lock_from_a_dead_process_does_not_block(self):
        dead = subprocess.Popen(["true"])
        dead.wait()
        os.symlink(f"{platform.node()}-{dead.pid}", os.path.join(self.udd, "SingletonLock"))
        r = self.run_script({"Default/Preferences": {"a": 2}})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.prefs(), {"a": 2})

    def test_dry_run_writes_nothing_and_names_the_change(self):
        self.write_prefs({"a": 1})
        r = self.run_script({"Default/Preferences": {"a": 2}, "external_extensions": {"x" * 32: "Ext"}}, "--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.prefs(), {"a": 1})
        self.assertIn("Would set in Default/Preferences: a", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.udd, "External Extensions")))

    @unittest.skipUnless(platform.system() == "Darwin", "per-user External Extensions is a macOS location")
    def test_extensions_get_a_web_store_file_on_macos(self):
        r = self.run_script({"external_extensions": {"a" * 32: "Ext"}})
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(self.udd, "External Extensions", "a" * 32 + ".json")) as f:
            self.assertEqual(json.load(f), {"external_update_url": "https://clients2.google.com/service/update2/crx"})

    @unittest.skipUnless(platform.system() == "Darwin", "per-user External Extensions is a macOS location")
    def test_extensions_alone_are_added_while_the_browser_is_open(self):
        os.symlink(f"{platform.node()}-{os.getpid()}", os.path.join(self.udd, "SingletonLock"))
        r = self.run_script({"external_extensions": {"a" * 32: "Ext"}})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.udd, "External Extensions", "a" * 32 + ".json")))

    def test_tracked_files_apply_cleanly(self):
        for browser in ("brave", "chrome"):
            with open(os.path.join(CONFIG, browser, "preferences.json")) as f:
                tracked = json.load(f)
            r = self.run_script(tracked, "--dry-run")
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_an_unknown_browser_is_refused(self):
        r = subprocess.run([sys.executable, SCRIPT, "firefox"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
