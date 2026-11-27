#!/usr/bin/env python3
"""macos-app-settings.py merges tracked app settings into defaults and exports without secrets."""
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "macos-app-settings.py")
# Stand-in for `defaults export|import TARGET -`: one plist file per target under $STORE.
FAKE_DEFAULTS = r'''#!/usr/bin/env python3
import os, sys
cmd, target = sys.argv[1], sys.argv[2]
path = os.path.join(os.environ["STORE"], target.replace("/", "%") + ".plist")
if os.environ.get("FAIL_IMPORT") and cmd == "import":
    sys.exit(1)
if cmd == "export":
    if not os.path.exists(path):
        sys.exit(1)
    sys.stdout.buffer.write(open(path, "rb").read())
elif cmd == "import":
    open(path, "wb").write(sys.stdin.buffer.read())
'''


class MacosAppSettings(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = tmp.name
        for d in ("bin", "store", "config", "home"):
            os.makedirs(os.path.join(self.root, d))
        self.write_tool("defaults", FAKE_DEFAULTS)
        self.write_tool("mdfind", "#!/bin/sh\n[ -n \"$SANDBOXED\" ] && echo /Applications/X.app\n")
        self.write_tool("codesign", "#!/bin/sh\necho com.apple.security.app-sandbox\n")

    def write_tool(self, name, body):
        path = os.path.join(self.root, "bin", name)
        with open(path, "w") as f:
            f.write(body)
        os.chmod(path, 0o755)

    def run_script(self, *args, **env):
        full = dict(os.environ, PATH=os.path.join(self.root, "bin") + os.pathsep + os.environ["PATH"],
                    STORE=os.path.join(self.root, "store"), MACOS_APP_SETTINGS_DIR=os.path.join(self.root, "config"),
                    HOME=os.path.join(self.root, "home"), **env)
        return subprocess.run([sys.executable, SCRIPT, *args], env=full, capture_output=True, text=True)

    def track(self, domain, data):
        with open(os.path.join(self.root, "config", domain + ".plist"), "wb") as f:
            plistlib.dump(data, f)

    def stored(self, target):
        path = os.path.join(self.root, "store", target.replace("/", "%") + ".plist")
        return plistlib.load(open(path, "rb")) if os.path.exists(path) else None

    def store(self, target, data):
        with open(os.path.join(self.root, "store", target.replace("/", "%") + ".plist"), "wb") as f:
            plistlib.dump(data, f)

    def test_apply_sets_tracked_keys_and_keeps_the_rest(self):
        self.store("a.app", {"keep": 1, "x": False})
        self.track("a.app", {"x": True, "y": "on"})
        r = self.run_script("apply")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.stored("a.app"), {"keep": 1, "x": True, "y": "on"})

    def test_dry_run_writes_nothing(self):
        self.store("a.app", {"x": False})
        self.track("a.app", {"x": True})
        r = self.run_script("apply", "--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.stored("a.app"), {"x": False})
        self.assertIn("Would set in a.app: x", r.stdout)

    def test_an_existing_container_gets_the_settings_inside_it(self):
        os.makedirs(os.path.join(self.root, "home", "Library", "Containers", "s.app"))
        self.track("s.app", {"x": True})
        r = self.run_script("apply", SANDBOXED="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        target = os.path.join(self.root, "home", "Library", "Containers", "s.app", "Data", "Library", "Preferences", "s.app")
        self.assertEqual(self.stored(target), {"x": True})
        self.assertIsNone(self.stored("s.app"))

    def test_a_sandboxed_app_without_a_container_is_skipped(self):
        self.track("s.app", {"x": True})
        r = self.run_script("apply", SANDBOXED="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIsNone(self.stored("s.app"))
        self.assertIn("start the app once", r.stdout)

    def test_a_failed_import_exits_1(self):
        self.track("a.app", {"x": True})
        r = self.run_script("apply", FAIL_IMPORT="1")
        self.assertEqual(r.returncode, 1)

    def test_export_drops_identities_secrets_times_and_geometry(self):
        self.store("a.app", {"CPU_state": True, "remote_id": "u", "api_token": "t", "support_ts": 1,
                             "NSWindow Frame Main": "0 0 1 1", "blob": b"\x00", "update-interval": "x",
                             "Sensors_state": False})
        r = self.run_script("export", "a.app")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(self.root, "config", "a.app.plist"), "rb") as f:
            self.assertEqual(plistlib.load(f), {"CPU_state": True, "Sensors_state": False})

    def test_export_of_an_unknown_domain_fails(self):
        self.assertEqual(self.run_script("export", "none.app").returncode, 1)


if __name__ == "__main__":
    unittest.main()
