import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = str(Path(__file__).resolve().parents[1]/'game-quirks')
EXPECT_STEAM_BLOCK = '''"apps"
\t\t\t\t{
\t\t\t\t\t"1282100"
\t\t\t\t\t{
\t\t\t\t\t\t"LastPlayed"\t\t"1"
\t\t\t\t\t}
\t\t\t\t\t"99"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"-windowed"
\t\t\t\t\t}
\t\t\t\t}
'''
LUTRIS_YML = """game:
  env:
    IGNORED: '1'
  exe: a.exe
name: Game
"""


class GameQuirks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.root = root
        apps = root/'steam/steamapps'
        apps.mkdir(parents=True)
        for appid, name in [('1282100', 'Remnant II'), ('99', 'Other'), ('1493710', 'Proton Experimental'), ('228980', 'Steamworks Common Redistributables')]:
            (apps/f'appmanifest_{appid}.acf').write_text(f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n')
        self.vdf = root/'steam/userdata/1/config/localconfig.vdf'
        self.vdf.parent.mkdir(parents=True)
        self.vdf.write_text(EXPECT_STEAM_BLOCK)
        (root/'games').mkdir()
        self.yml = root/'games/poe-1.yml'
        self.yml.write_text(LUTRIS_YML)
        db = sqlite3.connect(root/'pga.db')
        db.execute('create table games (slug text, name text, installed int, configpath text)')
        db.executemany('insert into games values (?,?,?,?)', [('poe', 'PoE', 1, 'poe-1'), ('gone', 'Gone', 0, '')])
        db.commit()
        db.close()
        fake = root/'bin'
        fake.mkdir()
        (fake/'pgrep').write_text('#!/bin/sh\nexit 1\n')
        (fake/'ops').write_text(f'#!/bin/sh\necho "$@" >> {root}/sent\n')
        for tool in fake.iterdir():
            tool.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{fake}:{os.environ["PATH"]}', 'GAME_QUIRKS_STEAM': str(root/'steam'),
                    'GAME_QUIRKS_LUTRIS_DB': str(root/'pga.db'), 'GAME_QUIRKS_LUTRIS_GAMES': str(root/'games'),
                    'GAME_QUIRKS_DECISIONS': str(root/'games.conf'), 'GAME_QUIRKS_NOTIFIED': str(root/'state/notified')}

    def run_tool(self, *args):
        return subprocess.run(['python3', SCRIPT, *args], env=self.env, capture_output=True, text=True, timeout=30)

    def sent(self):
        path = self.root/'sent'
        return path.read_text().splitlines() if path.exists() else []

    def test_new_game_is_flagged_tools_and_uninstalled_games_are_not(self):
        result = self.run_tool()
        self.assertEqual(result.returncode, 1)
        self.assertIn('steam:1282100', result.stdout)
        self.assertIn('lutris:poe', result.stdout)
        self.assertNotIn('Proton', result.stdout)
        self.assertNotIn('Steamworks', result.stdout)
        self.assertNotIn('Gone', result.stdout)

    def test_lutris_setting_goes_under_system_because_lutris_ignores_game_env(self):
        self.assertEqual(self.run_tool('afmf', 'lutris:poe').returncode, 0)
        text = self.yml.read_text()
        self.assertTrue(text.startswith(LUTRIS_YML))
        self.assertTrue(text.endswith("system:\n  env:\n    AFMF_ENABLE: '1'\n"))

    def test_lutris_keeps_an_existing_system_env(self):
        self.yml.write_text(LUTRIS_YML + "system:\n  gamemode: true\n  env:\n    A: b\nversion: x\n")
        self.run_tool('afmf', 'lutris:poe')
        self.assertIn("  env:\n    AFMF_ENABLE: '1'\n    A: b\nversion: x\n", self.yml.read_text())

    def test_lutris_env_in_a_later_section_is_not_used(self):
        self.yml.write_text(LUTRIS_YML + "system:\n  gamemode: true\nwine:\n  env:\n    A: b\n")
        self.run_tool('afmf', 'lutris:poe')
        self.assertIn("system:\n  env:\n    AFMF_ENABLE: '1'\n  gamemode: true\nwine:\n  env:\n    A: b\n", self.yml.read_text())

    def test_game_env_alone_does_not_count_as_enabled(self):
        self.yml.write_text(LUTRIS_YML.replace('IGNORED', 'AFMF_ENABLE'))
        (self.root/'games.conf').write_text('lutris:poe afmf\n')
        self.assertIn('SETTING MISSING', self.run_tool().stdout)

    def test_steam_adds_launch_options_only_to_that_game(self):
        self.run_tool('afmf', 'steam:1282100')
        text = self.vdf.read_text()
        self.assertIn('"1282100"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LaunchOptions"\t\t"AFMF_ENABLE=1 %command%"\n', text)
        self.assertIn('"LaunchOptions"\t\t"-windowed"', text)

    def test_steam_keeps_arguments_that_had_no_command_placeholder(self):
        self.run_tool('afmf', 'steam:99')
        self.assertIn('"AFMF_ENABLE=1 %command% -windowed"', self.vdf.read_text())

    def test_steam_is_left_alone_while_it_runs(self):
        (self.root/'bin/pgrep').write_text('#!/bin/sh\nexit 0\n')
        before = self.vdf.read_text()
        result = self.run_tool('afmf', 'steam:1282100')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.vdf.read_text(), before)
        self.assertFalse((self.root/'games.conf').exists())

    def test_running_twice_adds_nothing(self):
        self.run_tool('afmf', 'steam:1282100')
        self.run_tool('afmf', 'lutris:poe')
        vdf, yml = self.vdf.read_text(), self.yml.read_text()
        self.run_tool('afmf', 'steam:1282100')
        self.run_tool('afmf', 'lutris:poe')
        self.assertEqual((self.vdf.read_text(), self.yml.read_text()), (vdf, yml))
        self.assertEqual(len((self.root/'games.conf').read_text().splitlines()), 2)

    def test_a_decided_setting_that_disappears_is_reported(self):
        self.run_tool('afmf', 'lutris:poe')
        self.yml.write_text(LUTRIS_YML)
        result = self.run_tool()
        self.assertEqual(result.returncode, 1)
        self.assertIn('SETTING MISSING', result.stdout)

    def test_all_decided_exits_zero(self):
        self.run_tool('afmf', 'lutris:poe')
        self.run_tool('skip', 'steam:1282100', 'online only')
        self.run_tool('skip', 'steam:99', '2D')
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('online only', result.stdout)

    def test_notify_sends_once_and_again_only_for_a_new_game(self):
        self.run_tool('--notify')
        self.run_tool('--notify')
        self.assertEqual(len(self.sent()), 1)
        self.assertIn('Remnant II', self.sent()[0])
        (self.root/'steam/steamapps/appmanifest_5.acf').write_text('"appid"\t\t"5"\n"name"\t\t"Fresh"\n')
        self.run_tool('--notify')
        self.assertEqual(len(self.sent()), 2)
        self.assertIn('Fresh', self.sent()[1])
        self.assertNotIn('Remnant II', self.sent()[1])

    def test_steam_game_without_a_settings_block_asks_to_start_it_once(self):
        self.vdf.write_text(EXPECT_STEAM_BLOCK.replace('"1282100"', '"555"'))
        before = self.vdf.read_text()
        result = self.run_tool('afmf', 'steam:1282100')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('start the game once', result.stdout + result.stderr)
        self.assertEqual(self.vdf.read_text(), before)
        conf = self.root/'games.conf'
        self.assertNotIn('steam:1282100', conf.read_text() if conf.exists() else '')

    def test_skip_without_a_reason_is_a_usage_error(self):
        result = self.run_tool('skip', 'steam:99')
        self.assertNotEqual(result.returncode, 0)
        conf = self.root/'games.conf'
        self.assertNotIn('steam:99', conf.read_text() if conf.exists() else '')

    def test_unknown_game_is_refused(self):
        self.assertNotEqual(self.run_tool('afmf', 'steam:7').returncode, 0)
        self.assertFalse((self.root/'games.conf').exists())


if __name__ == '__main__':
    unittest.main()
