"""Behavior tests for system-update-guard. Run: python3 -m unittest discover -s system-update/tests"""

import builtins
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

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
        (self.dir / "proc").mkdir()
        self.env = dict(os.environ, SU_STATE_DIR=str(self.dir / "state"), SU_FEED_FILE=str(self.feed),
                        OPS_BIN=str(fake_ops), SU_UPDATE_CMD=f"touch {self.updated}",
                        SU_PROC_DIR=str(self.dir / "proc"))

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


    def test_pacnew_from_this_update_is_reported_even_with_an_old_package_mtime(self):
        self.feed.write_text(feed(OLD))
        etc = self.dir / "etc"
        (etc / "old").mkdir(parents=True)
        (etc / "old" / "before.conf.pacnew").write_text("x")
        fresh = etc / "sub" / "fresh.conf.pacnew"
        env = dict(self.env, SU_ETC_DIR=str(etc),
                   SU_UPDATE_CMD=f"sh -c 'mkdir -p {fresh.parent} && touch {fresh} && touch -t 200101010000 {fresh}'")
        self.assertEqual(self.guard(env=env).returncode, 0)
        self.assertIn("fresh.conf.pacnew", self.alerts_text())
        self.assertNotIn("before.conf.pacnew", self.alerts_text())

    def priority_env(self, **extra):
        fake = self.dir / "ops-priority"
        fake.write_text(f'#!/bin/sh\necho "$2|$3|$5" >> "{self.alerts}"\n')
        fake.chmod(0o755)
        return dict(self.env, OPS_BIN=str(fake), **extra)

    def stub_bin(self, name, body):
        bindir = self.dir / "bin"
        bindir.mkdir(exist_ok=True)
        path = bindir / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)
        return str(bindir)

    def seed(self, env=None):
        self.feed.write_text(feed(OLD))
        self.guard(env=env)
        if self.updated.exists():
            self.updated.unlink()
        if self.alerts.exists():
            self.alerts.unlink()

    def test_intervention_phrase_only_in_description_holds_the_update(self):
        self.seed()
        sneaky = dict(title="grub 2.14 released", slug="grub2", body="This needs Manual Intervention before reboot",
                      date="Thu, 22 Oct 2026 08:00:00 +0000")
        self.feed.write_text(feed(sneaky, OLD))
        self.assertEqual(self.guard().returncode, 3)
        self.assertFalse(self.updated.exists())
        self.assertIn("grub2", self.alerts_text())

    def test_other_intervention_phrasings_hold_the_update(self):
        for title, body in (("Intervention Required for foo", "details"),
                            ("foo 1.2 update", "this requires manual steps"),
                            ("foo 1.2 update", "manual intervention may be needed: intervention is required"),
                            ("foo 1.2 update", "intervention may be required when upgrading"),
                            ("foo 1.2 update", "this may require manual steps")):
            with self.subTest(title=title, body=body):
                self.seed()
                item = dict(title=title, slug="foo", body=body, date="Thu, 22 Oct 2026 08:00:00 +0000")
                self.feed.write_text(feed(item, OLD))
                self.assertEqual(self.guard().returncode, 3)
                self.assertFalse(self.updated.exists())

    def test_ack_stops_at_the_newest_item_so_a_late_listed_older_item_still_holds(self):
        self.feed.write_text(feed(OLD))
        self.assertEqual(self.guard("--ack").returncode, 0)
        late = dict(title="foo requires manual intervention", slug="late", body="details",
                    date="Tue, 06 Oct 2026 10:00:00 +0000")
        self.feed.write_text(feed(late, OLD))
        self.assertEqual(self.guard().returncode, 3)
        self.assertFalse(self.updated.exists())

    def test_two_informational_items_are_both_announced_once(self):
        self.seed()
        self.feed.write_text(feed(PHP, dict(title="Second note", slug="second", body="fyi",
                                            date="Tue, 20 Oct 2026 09:00:00 +0000"), OLD))
        self.assertEqual(self.guard().returncode, 0)
        self.assertTrue(self.updated.exists())
        self.assertIn("Update to php", self.alerts_text())
        self.assertIn("Second note", self.alerts_text())
        self.alerts.unlink()
        self.assertEqual(self.guard().returncode, 0)
        self.assertNotIn("Update to php", self.alerts_text())
        self.assertNotIn("Second note", self.alerts_text())

    def test_held_notification_has_priority_4(self):
        env = self.priority_env()
        self.seed(env)
        self.feed.write_text(feed(GRUB, OLD))
        self.assertEqual(self.guard(env=env).returncode, 3)
        lines = [line for line in self.alerts_text().splitlines() if "grub" in line]
        self.assertTrue(lines)
        self.assertTrue(all(line.endswith("|4") for line in lines), lines)

    def test_plain_news_announcement_has_priority_3(self):
        env = self.priority_env()
        self.seed(env)
        self.feed.write_text(feed(PHP, OLD))
        self.assertEqual(self.guard(env=env).returncode, 0)
        lines = [line for line in self.alerts_text().splitlines() if "php" in line]
        self.assertTrue(lines)
        self.assertTrue(all(line.endswith("|3") for line in lines), lines)

    def test_post_update_finding_has_priority_4(self):
        etc = self.dir / "etc"
        etc.mkdir()
        fresh = etc / "fresh.conf.pacnew"
        env = self.priority_env(SU_ETC_DIR=str(etc), SU_UPDATE_CMD=f"touch {fresh}")
        self.seed(dict(env, SU_UPDATE_CMD="true"))
        self.assertEqual(self.guard(env=env).returncode, 0)
        lines = [line for line in self.alerts_text().splitlines() if "fresh.conf.pacnew" in line]
        self.assertTrue(lines)
        self.assertTrue(all(line.endswith("|4") for line in lines), lines)

    def test_failed_system_and_user_units_are_both_reported(self):
        bindir = self.stub_bin("systemctl", 'case "$*" in *--user*) echo "user-unit.service loaded failed failed x";;'
                               ' *) echo "sys-unit.service loaded failed failed y";; esac\n')
        env = dict(self.env, PATH=bindir + os.pathsep + os.environ["PATH"])
        self.seed(env)
        self.assertEqual(self.guard(env=env).returncode, 0)
        text = self.alerts_text()
        self.assertIn("failed units after update", text)
        self.assertIn("sys-unit.service", text)
        self.assertIn("user-unit.service", text)

    def test_only_units_that_failed_since_the_update_started_are_reported(self):
        bindir = self.stub_bin("systemctl", """case "$*" in
  *--failed*) case "$*" in *--user*) ;; *)
    echo "before.service loaded failed failed x"
    echo "during.service loaded failed failed y"
    echo "unreadable.service loaded failed failed z";; esac;;
  *before.service*) echo @1000;;
  *during.service*) echo @9999999999;;
  *unreadable.service*) echo n/a;;
esac
""")
        env = dict(self.env, PATH=bindir + os.pathsep + os.environ["PATH"])
        self.seed(env)
        self.assertEqual(self.guard(env=env).returncode, 0)
        text = self.alerts_text()
        self.assertNotIn("before.service", text)
        self.assertIn("during.service", text)
        self.assertIn("unreadable.service", text)

    def test_only_old_failures_send_no_failed_units_alert(self):
        bindir = self.stub_bin("systemctl", """case "$*" in
  *--failed*) case "$*" in *--user*) ;; *) echo "before.service loaded failed failed x";; esac;;
  *before.service*) echo @1000;;
esac
""")
        env = dict(self.env, PATH=bindir + os.pathsep + os.environ["PATH"])
        self.seed(env)
        self.assertEqual(self.guard(env=env).returncode, 0)
        self.assertNotIn("failed units", self.alerts_text())

    def test_old_user_unit_failure_reads_its_time_from_the_user_manager(self):
        bindir = self.stub_bin("systemctl", """case "$*" in
  *--failed*) case "$*" in *--user*) echo "old-user.service loaded failed failed x";; esac;;
  *--user*old-user.service*) echo @1000;;
esac
""")
        env = dict(self.env, PATH=bindir + os.pathsep + os.environ["PATH"])
        self.seed(env)
        self.assertEqual(self.guard(env=env).returncode, 0)
        self.assertNotIn("old-user.service", self.alerts_text())


class NvidiaTest(unittest.TestCase):
    def findings(self, loaded, installed):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        bindir = Path(tmp.name)
        for name, body in (("pacman", f'echo "nvidia-utils {installed}"\n'), ("systemctl", "exit 0\n")):
            path = bindir / name
            path.write_text("#!/bin/sh\n" + body)
            path.chmod(0o755)
        etc = Path(tmp.name) / "etc"
        etc.mkdir()
        loader = importlib.machinery.SourceFileLoader("guard", str(GUARD))
        spec = importlib.util.spec_from_loader("guard", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        real_open = builtins.open

        def fake_open(file, *args, **kwargs):
            if str(file) == "/sys/module/nvidia/version":
                import io
                return io.StringIO(loaded + "\n")
            return real_open(file, *args, **kwargs)

        env = {"PATH": str(bindir) + os.pathsep + os.environ["PATH"]}
        with mock.patch.dict(os.environ, env), mock.patch.object(builtins, "open", fake_open), \
                mock.patch.object(module, "ETC_DIR", str(etc)), mock.patch("os.path.isdir", return_value=True):
            result = module.post_checks(0.0)
        self.assertNotIn("new .pacnew files", [t for t, _ in result], "the test read the real /etc")
        return [(t, m) for t, m in result if "nvidia" in (t + m).lower()]

    def test_differing_versions_report_reboot_needed_naming_both(self):
        found = self.findings("580.82.09", "580.95.05-1")
        self.assertEqual(len(found), 1)
        text = " ".join(found[0])
        self.assertIn("reboot", text.lower())
        self.assertIn("580.82.09", text)
        self.assertIn("580.95.05", text)

    def test_equal_versions_report_nothing(self):
        self.assertEqual(self.findings("580.95.05", "580.95.05-1"), [])


ENGINE = "7fa2ce000000-7fa2ce0bc000 r--p 00000000 103:02 49464850                  /usr/lib/libQt6WebEngineCore.so.6.11.3"
SHM = "7fa2cd000000-7fa2cd0bc000 r--s 00000000 00:1b 5120                       /dev/shm/.org.chromium.Chromium.uPzkeN (deleted)"


class ZapZapRestartTest(unittest.TestCase):
    """The fake /proc holds the processes; a fake kill removes one, as a real exit would."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.proc = Path(tmp.name)
        (self.proc / "cpuinfo").write_text("not a process\n")
        loader = importlib.machinery.SourceFileLoader("guard", str(GUARD))
        self.module = importlib.util.module_from_spec(importlib.util.spec_from_loader("guard", loader))
        loader.exec_module(self.module)
        self.killed, self.started, self.hung = [], [], set()

    def process(self, pid, cmdline, *maps):
        path = self.proc / str(pid)
        path.mkdir()
        (path / "cmdline").write_bytes(b"\0".join(part.encode() for part in cmdline) + b"\0")
        (path / "maps").write_text("".join(line + "\n" for line in maps))

    def zapzap(self, pid, *maps):
        self.process(pid, ["/usr/bin/python", "/usr/bin/zapzap", ""], *maps)

    def run_restart(self, start_code=0):
        def fake_kill(pid, sig):
            self.killed.append((pid, sig))
            if pid not in self.hung:
                for name in ("cmdline", "maps"):
                    (self.proc / str(pid) / name).unlink()
                (self.proc / str(pid)).rmdir()

        def fake_run(cmd, **kwargs):
            self.started.append((cmd, sorted(p.name for p in self.proc.iterdir() if p.name.isdigit())))
            return mock.Mock(returncode=start_code)

        with mock.patch.object(self.module, "PROC_DIR", str(self.proc)), \
                mock.patch.object(self.module, "ZAPZAP_QUIT_WAIT", 0.2), \
                mock.patch.object(self.module.os, "kill", fake_kill), \
                mock.patch.object(self.module.subprocess, "run", fake_run):
            return self.module.restart_stale_zapzap()

    def test_copy_on_a_replaced_engine_is_stopped_then_started_once(self):
        self.zapzap(518433, SHM, ENGINE + " (deleted)")
        self.assertIsNone(self.run_restart())
        self.assertEqual(self.killed, [(518433, self.module.signal.SIGTERM)])
        self.assertEqual(len(self.started), 1)
        self.assertEqual(self.started[0][1], [], "started while the old copy was still alive")
        self.assertIn("/usr/bin/zapzap", self.started[0][0])

    def test_healthy_copy_with_only_deleted_shared_memory_is_left_alone(self):
        self.zapzap(1932689, SHM, ENGINE)
        self.assertIsNone(self.run_restart())
        self.assertEqual((self.killed, self.started), ([], []))

    def test_other_program_on_replaced_files_is_left_alone(self):
        self.process(4242, ["/usr/bin/python", "/usr/bin/other-app"], ENGINE + " (deleted)")
        self.process(4243, ["/usr/bin/zapzap-helper"], ENGINE + " (deleted)")
        self.assertIsNone(self.run_restart())
        self.assertEqual((self.killed, self.started), ([], []))

    def test_no_zapzap_running_starts_nothing(self):
        self.assertIsNone(self.run_restart())
        self.assertEqual(self.started, [])

    def test_second_copy_is_stopped_too_so_one_copy_owns_the_profile(self):
        self.zapzap(518433, ENGINE + " (deleted)")
        self.zapzap(1922296, ENGINE)
        self.assertIsNone(self.run_restart())
        self.assertEqual(sorted(pid for pid, _ in self.killed), [518433, 1922296])
        self.assertEqual(len(self.started), 1)

    def test_copy_that_does_not_quit_is_reported_and_no_second_copy_starts(self):
        self.zapzap(518433, ENGINE + " (deleted)")
        self.hung.add(518433)
        finding = self.run_restart()
        self.assertEqual(self.started, [])
        self.assertEqual(finding[0], "ZapZap not restarted")
        self.assertIn("did not quit", finding[1])

    def test_failed_start_is_reported(self):
        self.zapzap(518433, ENGINE + " (deleted)")
        finding = self.run_restart(start_code=1)
        self.assertEqual(finding[0], "ZapZap not restarted")
        self.assertIn("exited 1", finding[1])

    def test_process_that_vanishes_between_listing_and_reading_is_ignored(self):
        self.zapzap(518433, ENGINE + " (deleted)")
        (self.proc / "518433" / "maps").unlink()
        self.assertIsNone(self.run_restart())
        self.assertEqual((self.killed, self.started), ([], []))

    def test_guard_run_reports_a_copy_that_does_not_quit(self):
        # End to end through main(): a fake pid nobody can signal stays listed, so the guard must alert.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        work = Path(tmp.name)
        alerts = work / "alerts"
        ops = work / "ops"
        ops.write_text(f'#!/bin/sh\necho "$2|$3" >> "{alerts}"\n')
        ops.chmod(0o755)
        (work / "feed.xml").write_text(feed(OLD))
        self.zapzap(4194999, ENGINE + " (deleted)")  # above pid_max: the signal finds no process
        env = dict(os.environ, SU_STATE_DIR=str(work / "state"), SU_FEED_FILE=str(work / "feed.xml"),
                   OPS_BIN=str(ops), SU_UPDATE_CMD="true", SU_PROC_DIR=str(self.proc), SU_ZAPZAP_QUIT_WAIT="0.2",
                   SU_ZAPZAP_START=f"touch {work / 'started'}")
        result = subprocess.run([str(GUARD)], capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ZapZap not restarted|", alerts.read_text())
        self.assertFalse((work / "started").exists(), "started a second copy beside the stuck one")


if __name__ == "__main__":
    unittest.main()
