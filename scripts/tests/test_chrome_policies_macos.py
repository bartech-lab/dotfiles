#!/usr/bin/env python3
"""chrome-policies-macos.py writes each policy with the defaults type that matches its JSON type."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "chrome-policies-macos.py")


class ChromePoliciesMacos(unittest.TestCase):
    def run_script(self, policies, *extra):
        with tempfile.TemporaryDirectory() as tmp:
            log = os.path.join(tmp, "calls")
            fake = os.path.join(tmp, "defaults")
            with open(fake, "w") as f:
                f.write(f'#!/bin/sh\nprintf "%s|" "$@" >> "{log}"\necho >> "{log}"\n')
            os.chmod(fake, 0o755)
            src = os.path.join(tmp, "p.json")
            with open(src, "w") as f:
                json.dump(policies, f)
            env = {**os.environ, "PATH": tmp + os.pathsep + os.environ["PATH"]}
            result = subprocess.run([sys.executable, SCRIPT, *extra, src], env=env,
                                    capture_output=True, text=True)
            calls = open(log).read().splitlines() if os.path.exists(log) else []
            return result, calls

    def test_each_json_type_gets_its_defaults_type(self):
        result, calls = self.run_script({"A": False, "B": 2, "C": "x y", "D": ["en-US", "pl"]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [
            "write|com.google.Chrome|A|-bool|false|",
            "write|com.google.Chrome|B|-int|2|",
            "write|com.google.Chrome|C|-string|x y|",
            "write|com.google.Chrome|D|-array|en-US|pl|",
        ])

    def test_dry_run_writes_nothing(self):
        result, calls = self.run_script({"A": True}, "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])
        self.assertIn("defaults write com.google.Chrome A -bool true", result.stdout)

    def test_unsupported_value_fails_before_any_write(self):
        result, calls = self.run_script({"A": True, "B": {"nested": 1}})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_tracked_policy_file_is_fully_supported(self):
        result, _ = self.run_script(json.load(open(os.path.join(
            os.path.dirname(SCRIPT), "..", "linux", "etc", "opt", "chrome", "policies",
            "recommended", "plain.json"))), "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
