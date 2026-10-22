"""Behavior tests for system-update-guard. Run: python3 -m unittest discover -s system-update/tests"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[1] / "system-update-guard"

ITEM = """<item><title>{title}</title><link>https://archlinux.org/news/{slug}/</link>
<description>{body}</description><pubDate>{date}</pubDate></item>"""


def feed(*items):
    return '<?xml version="1.0"?><rss version="2.0"><channel>' + "".join(ITEM.format(**i) for i in items) + "</channel></rss>"


OLD = dict(title="Old note", slug="old", body="nothing to do", date="Mon, 05 Oct 2026 10:00:00 +0000")
PHP = dict(title="Update to php 8.5.12", slug="php", body="update to prevent remote code execution",
           date="Wed, 21 Oct 2026 19:29:36 +0000")
GRUB = dict(title="grub 2.14 requires manual intervention", slug="grub", body="run grub-install",
            date="Thu, 22 Oct 2026 08:00:00 +0000")


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.feed = self.dir / "feed.xml"
        self.updated = self.dir / "updated"
        self.alerts = self.dir / "alerts"
        fake_ops = self.dir / "ops"
        fake_ops.write_text(f'#!/bin/sh\necho "$2|$3" >> "{self.alerts}"\n')
        fake_ops.chmod(0o755)
        self.env = dict(os.environ, SU_STATE_DIR=str(self.dir / "state"), SU_FEED_FILE=str(self.feed),
                        OPS_BIN=str(fake_ops), SU_UPDATE_CMD=f"touch {self.updated}")

    def tearDown(self):
        self.tmp.cleanup()

    def guard(self, *args, env=None):
        return subprocess.run([str(GUARD), *args], capture_output=True, text=True, env=env or self.env)

    def alerts_text(self):
        return self.alerts.read_text() if self.alerts.exists() else ""

    def test_first_run_does_not_block_on_news_published_before_it(self):
        self.feed.write_text(feed(GRUB, OLD))
        self.assertEqual(self.guard().returncode, 0)
        self.assertTrue(self.updated.exists())

    def test_new_intervention_item_holds_the_update_until_ack(self):
        self.feed.write_text(feed(OLD))
        self.guard()
        self.updated.unlink()
        self.feed.write_text(feed(GRUB, PHP, OLD))
        result = self.guard()
        self.assertEqual(result.returncode, 3)
        self.assertFalse(self.updated.exists())
        self.assertIn("Arch update held|manual intervention: grub", self.alerts_text())
        self.assertEqual(self.guard().returncode, 3, "a held update stays held on the next run")
        self.assertEqual(self.guard("--ack").returncode, 0)
        self.assertEqual(self.guard().returncode, 0)
        self.assertTrue(self.updated.exists())

    def test_security_news_without_intervention_is_announced_once_and_update_runs(self):
        self.feed.write_text(feed(OLD))
        self.guard()
        self.feed.write_text(feed(PHP, OLD))
        self.assertEqual(self.guard().returncode, 0)
        self.assertTrue(self.updated.exists())
        self.guard()
        self.assertEqual(self.alerts_text().count("Arch news|Update to php"), 1)

    def test_unreachable_feed_updates_and_says_news_was_unchecked(self):
        env = dict(self.env, SU_FEED_FILE=str(self.dir / "missing.xml"))
        self.assertEqual(self.guard(env=env).returncode, 0)
        self.assertTrue(self.updated.exists())
        self.assertIn("Arch news unchecked", self.alerts_text())

    def test_help_and_unknown_arguments_never_run_the_update(self):
        self.feed.write_text(feed(OLD))
        self.assertEqual(self.guard("--help").returncode, 0)
        self.assertEqual(self.guard("--dry-run").returncode, 2)
        self.assertFalse(self.updated.exists())

    def test_failed_update_passes_its_exit_code(self):
        self.feed.write_text(feed(OLD))
        env = dict(self.env, SU_UPDATE_CMD="sh -c 'exit 7'")
        self.assertEqual(self.guard(env=env).returncode, 7)


if __name__ == "__main__":
    unittest.main()
