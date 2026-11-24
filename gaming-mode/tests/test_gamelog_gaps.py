"""Spec-derived tests: secret filtering, backfill, end-of-session notification."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
import test_gamelog as base  # noqa: E402

SECRET_NAMES = ['MY_TOKEN', 'Wine_Api_Key', 'db_secret', 'PASSWORD_X', 'user_credential', 'Cookie_Jar', 'AUTH_HEADER']


def planted(n):
    return f'PLANTED-SECRET-{n}'


def raw_values(*groups):
    return [v for g in groups for v in g.values()]


class SecretsNeverRecorded(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='gamelog-gaps.')
        cls.addClassCleanup(shutil.rmtree, cls.tmp, True)
        cls.lutris_secret = {name: planted(i) for i, name in enumerate(SECRET_NAMES, 1)}
        cls.proc_secret = {
            'PROTON_AUTH_TOKEN': planted(11), 'Wine_Api_Key': planted(12), 'WINE_PASSWORD': planted(13),
            'DXVK_session_cookie': planted(14), 'VK_Credential_File': planted(15), 'SDL_secret_thing': planted(16),
            'ENABLE_AUTH_MODE': planted(17), 'NOTALLOWED_VAR': planted(18), 'HOME': planted(19),
        }
        cls.proc_ok = {'PROTON_LOG': '1', 'WINEDEBUG': '-all', 'DXVK_HUD': 'fps', 'SDL_VIDEODRIVER': 'x11',
                       'DISPLAY': ':0', 'ENABLE_ORDINARY': 'yes'}
        cls.ini_secret = {'login_token': planted(21), 'Session_ID': planted(22), 'PassWord': planted(23),
                          'saved_credential': planted(24), 'user_email': planted(25),
                          'account_name': planted(26), 'auto_login': planted(27)}
        cls.sim = base.Sim(cls.tmp, 'secrets', [
            ['proc', 4242, {**cls.proc_ok, **cls.proc_secret}], ['sleep', 1.5], ['rmproc', 4242]])
        r = cls.sim.root
        lutris = "name: Game\nsystem:\n  env:\n    ORDINARY_FLAG: 'ordinary-value'\n    GPU_MODE: 'fast'\n"
        lutris += ''.join(f"    {k}: '{v}'\n" for k, v in cls.lutris_secret.items())
        lutris += 'runner: wine\n'
        (r / 'lutris' / 'path-of-exile-2.yml').write_text(lutris)
        ini = ('[DISPLAY]\nrenderer_type=Vulkan\nvsync=Off\n'
               f'login_token={planted(21)}\nSession_ID={planted(22)}\n'
               '[NETWORKING]\nnetworking_type=predictive\n'
               f'PassWord={planted(23)}\nsaved_credential={planted(24)}\n'
               '[GENERAL]\nengine_multithreading_mode=enabled\n'
               f'user_email={planted(25)}\naccount_name={planted(26)}\n'
               '[SOUND]\nmaster_volume=50\n'
               f'auto_login={planted(27)}\n'
               '[LOGIN]\ngateway_id=outside-section\n')
        (r / 'game' / 'production_Config.ini').write_text(ini)
        cls.sim.start()
        cls.sim.finish()
        cls.meta_text = (cls.sim.session() / 'meta.json').read_text()
        cls.ini_text = (cls.sim.session() / 'config.ini').read_text()
        cls.meta = json.loads(cls.meta_text)

    def test_session_was_recorded(self):
        self.assertEqual(self.sim.rc, 0, self.sim.err)

    def test_lutris_env_keeps_ordinary_variables(self):
        env = self.meta['settings']['lutris_env']
        self.assertEqual(env.get('ORDINARY_FLAG'), 'ordinary-value')
        self.assertEqual(env.get('GPU_MODE'), 'fast')

    def test_lutris_env_drops_secret_names_in_any_case(self):
        env = self.meta['settings']['lutris_env']
        for name in SECRET_NAMES:
            with self.subTest(name=name):
                self.assertNotIn(name, env)

    def test_process_env_keeps_allowed_ordinary_variables(self):
        env = self.meta['process']['env']
        for k, v in self.proc_ok.items():
            with self.subTest(k=k):
                self.assertEqual(env.get(k), v)

    def test_process_env_drops_secret_and_unlisted_names(self):
        env = self.meta['process']['env']
        for k in self.proc_secret:
            with self.subTest(k=k):
                self.assertNotIn(k, env)

    def test_ini_keeps_ordinary_lines_in_kept_sections(self):
        for line in ('renderer_type=Vulkan', 'vsync=Off', 'networking_type=predictive',
                     'engine_multithreading_mode=enabled', 'master_volume=50'):
            with self.subTest(line=line):
                self.assertIn(line, self.ini_text)

    def test_ini_drops_other_sections(self):
        self.assertNotIn('gateway_id', self.ini_text)
        self.assertNotIn('[LOGIN]', self.ini_text)

    def test_no_planted_value_in_meta_or_config(self):
        values = raw_values(self.lutris_secret, self.proc_secret, self.ini_secret)
        for text, name in ((self.meta_text, 'meta.json'), (self.ini_text, 'config.ini')):
            for v in values:
                with self.subTest(file=name, value=v):
                    self.assertNotIn(v, text)


def ts(dt):
    return dt.strftime('%Y/%m/%d %H:%M:%S')


START = '[STARTUP] Game Start'
ZONE = 'Generating level 80 area "Zone%d" with seed %d'
VRAM = '[TEXTURE] Insufficient VRAM'
CONNECT = 'Connect time to instance server was 26ms'
DISC = 'Abnormal disconnect: An unexpected disconnection occurred.'
GRACEFUL = 'Closing game gracefully'
T0 = datetime(2024, 7, 15, 12, 0, 0)


class Backfill(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='gamelog-backfill.')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = Path(os.path.realpath(self.tmp))
        (self.root / 'game').mkdir()

    def log(self, events):
        lines = [base.mk_line(msg, stamp=ts(T0 + timedelta(seconds=sec)), nl='\r\n') for sec, msg in events]
        (self.root / 'game' / 'Client.txt').write_text(''.join(lines), newline='')

    def run_backfill(self):
        r = subprocess.run([base.GAMELOG, 'backfill'], env=base.base_env(self.root, TZ='UTC'), cwd=self.root,
                           capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        p = self.root / 'state' / 'backfill.json'
        return r, json.loads(p.read_text()) if p.exists() else None

    def test_two_runs_with_different_counts(self):
        ev = [(0, START), (10, ZONE % (1, 1)), (20, VRAM), (30, ZONE % (2, 2)), (40, VRAM), (50, VRAM),
              (60, CONNECT), (70, DISC), (80, GRACEFUL),
              (1000, START), (1010, ZONE % (3, 3)), (1020, ZONE % (4, 4)), (1030, ZONE % (5, 5)),
              (1040, VRAM), (1050, CONNECT), (1060, DISC), (1070, CONNECT), (1080, DISC)]
        self.log(ev)
        r, runs = self.run_backfill()
        self.assertEqual(len(runs), 2)
        self.assertEqual([x['zones'] for x in runs], [2, 3])
        self.assertEqual([x['vram_warnings'] for x in runs], [3, 1])
        self.assertEqual([x['disconnects'] for x in runs], [1, 2])
        self.assertEqual([x['graceful'] for x in runs], [True, False])
        for x in runs:
            self.assertLessEqual(x['start'], x['end'])
            for k in ('start', 'end', 'zones', 'vram_warnings', 'disconnects', 'graceful'):
                self.assertIn(k, x)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[-1], '2 sessions, 1 without a clean exit, 4 memory warnings, 3 disconnects')
        run_lines = lines[1:-1]
        self.assertEqual(len(run_lines), 2, r.stdout)
        self.assertTrue(run_lines[0].rstrip().endswith('yes'), run_lines[0])
        self.assertTrue(run_lines[1].rstrip().endswith('NO'), run_lines[1])

    def test_run_without_a_zone_is_dropped(self):
        self.log([(0, START), (10, ZONE % (1, 1)), (20, GRACEFUL), (1000, START), (1010, VRAM)])
        r, runs = self.run_backfill()
        self.assertEqual(len(runs), 1)
        self.assertEqual(runs[0]['zones'], 1)
        self.assertEqual(r.stdout.splitlines()[-1], '1 sessions, 0 without a clean exit, 0 memory warnings, 0 disconnects')

    def test_gap_over_1800_seconds_splits_without_a_start_line(self):
        self.log([(0, START), (10, ZONE % (1, 1)), (1810 + 10, ZONE % (2, 2))])
        _, runs = self.run_backfill()
        self.assertEqual([x['zones'] for x in runs], [1, 1])

    def test_gap_under_1800_seconds_does_not_split(self):
        self.log([(0, START), (10, ZONE % (1, 1)), (10 + 1790, ZONE % (2, 2))])
        _, runs = self.run_backfill()
        self.assertEqual([x['zones'] for x in runs], [2])

    def test_clean_exit_starts_a_new_run_without_a_start_line(self):
        self.log([(0, START), (10, ZONE % (1, 1)), (20, GRACEFUL), (30, ZONE % (2, 2))])
        _, runs = self.run_backfill()
        self.assertEqual([(x['zones'], x['graceful']) for x in runs], [(1, True), (1, False)])

    def test_empty_log(self):
        self.log([])
        r, runs = self.run_backfill()
        self.assertEqual(runs, [])
        self.assertEqual(r.stdout.splitlines()[-1], '0 sessions, 0 without a clean exit, 0 memory warnings, 0 disconnects')


def loading(name='Zone1'):
    return base.L(f'[LOADING SCREEN] ({name}) Duration = 1.5 seconds')


class SessionNotification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='gamelog-notify.')
        cls.addClassCleanup(shutil.rmtree, cls.tmp, True)
        game = [['proc', 4242, dict(base.GAME_ENV)], ['sleep', 0.6]]
        play = (base.L(START) + base.L(ZONE % (1, 1)) + loading())
        csv = ['csv', 'PathOfExile.exe_{TSFILE}.csv', base.csv_text(15)]
        cls.S = {
            'clean': base.Sim(cls.tmp, 'clean', game + [['append', play], ['sleep', 1.8],
                                                        csv, ['append', base.L(GRACEFUL)], ['rmproc', 4242]], full=True, nvidia='hang'),
            'bad': base.Sim(cls.tmp, 'bad', game + [['append', play], ['sleep', 1.8], csv, ['rmproc', 4242]], full=True, nvidia='hang'),
            'noarea': base.Sim(cls.tmp, 'noarea', game + [['append', base.L(START)], ['sleep', 1.2], csv,
                                                          ['rmproc', 4242]], full=True, nvidia='hang'),
        }
        for s in cls.S.values():
            cls.addClassCleanup(s.kill_stubs)
            s.start()
        for s in cls.S.values():
            s.finish()

    def one_note(self, key):
        s = self.S[key]
        self.assertEqual(s.rc, 0, s.err)
        notes = s.notes()
        self.assertEqual(len(notes), 1, notes)
        n = notes[0]
        self.assertEqual(n[0], 'notify')
        self.assertEqual(n[-2], '--priority')
        return n

    def test_clean_session_is_priority_3_with_numbers_and_nothing_unusual(self):
        n = self.one_note('clean')
        self.assertEqual(n[1], 'PoE2 session')
        self.assertEqual(n[-1], '3')
        self.assertRegex(n[2], r'^\d+ fps average, \d+ fps 1% low, [\d.]+ stutters per 10 min')
        self.assertIn('Nothing unusual.', n[2])

    def test_session_with_a_bad_finding_is_priority_4(self):
        n = self.one_note('bad')
        findings = json.loads((self.S['bad'].session() / 'summary.json').read_text())['findings']
        self.assertTrue(any(f['level'] == 'bad' for f in findings), findings)
        self.assertEqual(n[1], 'PoE2 session')
        self.assertEqual(n[-1], '4')
        self.assertRegex(n[2], r'^\d+ fps average, \d+ fps 1% low, [\d.]+ stutters per 10 min')
        self.assertNotIn('Nothing unusual.', n[2])

    def test_session_without_an_area_is_priority_2_with_no_play_numbers(self):
        n = self.one_note('noarea')
        self.assertEqual(n[1], 'PoE2 session')
        self.assertEqual(n[-1], '2')
        self.assertIn('no play numbers', n[2])


if __name__ == '__main__':
    unittest.main()
