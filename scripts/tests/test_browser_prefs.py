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


@unittest.skipUnless(platform.system() == "Darwin", "per-user External Extensions is a macOS location")
class ShareInstalled(unittest.TestCase):
    """--share-installed offers every hand-installed Web Store extension to all profiles."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.udd = tmp.name

    def profiles(self, **prefs):
        """prefs: profile dir -> {file name: extensions.settings dict}"""
        with open(os.path.join(self.udd, "Local State"), "w") as f:
            json.dump({"profile": {"info_cache": {p: {} for p in prefs}}}, f)
        for profile, files in prefs.items():
            os.makedirs(os.path.join(self.udd, profile), exist_ok=True)
            for name, settings in files.items():
                with open(os.path.join(self.udd, profile, name), "w") as f:
                    f.write(settings if isinstance(settings, str) else json.dumps({"extensions": {"settings": settings}}))

    def run_share(self, *extra):
        return subprocess.run([sys.executable, SCRIPT, "chrome", "--share-installed", *extra, "--user-data-dir", self.udd],
                              capture_output=True, text=True)

    def offered(self):
        d = os.path.join(self.udd, "External Extensions")
        return sorted(n[:-5] for n in os.listdir(d)) if os.path.isdir(d) else []

    @staticmethod
    def ext(location=1, webstore=True, **extra):
        return {"from_webstore": webstore, "location": location, "manifest": {"name": "N"}, **extra}

    def test_hand_installed_in_a_second_profile_is_offered(self):
        self.profiles(**{"Default": {"Preferences": {}},
                         "Profile 2": {"Secure Preferences": {"b" * 32: self.ext()}}})
        r = self.run_share()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.offered(), ["b" * 32])

    def test_preinstalled_unpacked_and_already_external_are_skipped(self):
        self.profiles(Default={"Preferences": {
            "c" * 32: self.ext(was_installed_by_default=True),
            "d" * 32: self.ext(location=4, webstore=False),
            "e" * 32: self.ext(location=6),
            "f" * 32: self.ext(location=5),
        }})
        r = self.run_share()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.offered(), [])

    def test_existing_files_are_never_removed_or_rewritten(self):
        os.makedirs(os.path.join(self.udd, "External Extensions"))
        kept = os.path.join(self.udd, "External Extensions", "a" * 32 + ".json")
        with open(kept, "w") as f:
            f.write("custom")
        self.profiles(Default={"Preferences": {"a" * 32: self.ext()}})
        r = self.run_share()
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(kept) as f:
            self.assertEqual(f.read(), "custom")

    def test_an_unreadable_profile_fails_but_the_others_are_still_shared(self):
        self.profiles(**{"Default": {"Preferences": "{broken"},
                         "Profile 2": {"Preferences": {"b" * 32: self.ext()}}})
        r = self.run_share()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Default", r.stderr)
        self.assertEqual(self.offered(), ["b" * 32])

    def test_dry_run_writes_nothing(self):
        self.profiles(Default={"Preferences": {"b" * 32: self.ext()}})
        r = self.run_share("--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Would offer extension", r.stdout)
        self.assertEqual(self.offered(), [])


if __name__ == "__main__":
    unittest.main()
