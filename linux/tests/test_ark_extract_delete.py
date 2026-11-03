"""Behavior tests for ark-extract-delete with a fake ark. Run: python3 -m unittest linux/tests/test_ark_extract_delete.py"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "ark-extract-delete"
FAKE_ARK = """#!/bin/bash
for a; do :; done
case "$ARK_MODE" in
  extract) mkdir -p "${a%.zip}" ;;
  nothing) ;;
  fail) exit 1 ;;
esac
"""


class ArkExtractDelete(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        (base / "bin").mkdir()
        ark = base / "bin" / "ark"
        ark.write_text(FAKE_ARK)
        ark.chmod(0o755)
        self.work = base / "work"
        self.work.mkdir()
        self.path = f"{base / 'bin'}:{os.environ['PATH']}"

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, mode, *names):
        archives = []
        for name in names:
            archive = self.work / name
            archive.write_text("data")
            archives.append(archive)
        env = {**os.environ, "PATH": self.path, "ARK_MODE": mode}
        result = subprocess.run([str(SCRIPT), *map(str, archives)], env=env, capture_output=True, text=True)
        return result, archives

    def test_an_extracted_archive_is_deleted(self):
        result, [archive] = self.run_script("extract", "a.zip")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(archive.exists())

    def test_an_archive_is_kept_when_ark_succeeds_but_extracts_nothing(self):
        result, [archive] = self.run_script("nothing", "a.zip")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(archive.exists())
        self.assertIn("kept", result.stderr)

    def test_an_archive_is_kept_when_ark_fails(self):
        result, [archive] = self.run_script("fail", "a.zip")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(archive.exists())


if __name__ == "__main__":
    unittest.main()
