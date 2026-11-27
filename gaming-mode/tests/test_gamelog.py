"""Spec-derived tests for gamelog (lutris_env, capture, CLI).

The tool directory comes from GAMELOG_TOOL_DIR (default: the parent of tests/).
"""
import calendar
import gzip
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

if not sys.platform.startswith('linux'):
    print('skip: Linux only')
    raise SystemExit(0)
from datetime import datetime, timedelta
from pathlib import Path

sys.dont_write_bytecode = True
TOOL = os.environ.get('GAMELOG_TOOL_DIR') or str(Path(__file__).resolve().parents[1])
sys.path.insert(0, TOOL)
from gamelog_lib import lutris_env  # noqa: E402

GAMELOG = os.path.join(TOOL, 'gamelog')
REAL_PATH = '/usr/local/bin:/usr/bin:/bin'
PRELUDE = ("import sys, json, os\nsys.dont_write_bytecode = True\n"
           "sys.path.insert(0, os.environ['GAMELOG_TOOL_DIR'])\n"
           "from gamelog_lib import capture as c\n")


def base_env(root, **extra):
    root = str(root)
    env = {
        'PATH': REAL_PATH, 'HOME': f'{root}/home', 'XDG_STATE_HOME': f'{root}/xdg-state',
        'XDG_CONFIG_HOME': f'{root}/xdg-config', 'XDG_RUNTIME_DIR': f'{root}/xdg-run',
        'PYTHONDONTWRITEBYTECODE': '1', 'GAMELOG_TOOL_DIR': TOOL, 'LANG': 'C.UTF-8',
        'GAMELOG_STATE': f'{root}/state', 'GAMELOG_PROC': f'{root}/proc', 'GAMELOG_SYS': f'{root}/sys',
        'GAMELOG_GAME_DIR': f'{root}/game', 'GAMELOG_CLIENT_LOG': f'{root}/game/Client.txt',
        'GAMELOG_INI': f'{root}/game/production_Config.ini', 'GAMELOG_LUTRIS_GAMES': f'{root}/lutris',
        'GAMELOG_MANGO_CONF': f'{root}/mango/MangoHud.conf', 'GAMELOG_NOTIFY': f'{root}/no-such-notifier',
        'GAMELOG_INTERVAL': '0.1', 'GAMELOG_START_WAIT': '2', 'GAMELOG_RESTART_WAIT': '1',
        'GAMELOG_MIN_SECONDS': '1',
    }
    env.update({k: str(v) for k, v in extra.items()})
    return env


def mk_line(msg, level='INFO', stamp='2024/07/15 12:34:56', up=123456, nl='\r\n'):
    return f'{stamp} {up} cffb0719 [{level} Client 416] {msg}{nl}'


class CapCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='gamelog-unit.')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = Path(os.path.realpath(self.tmp))

    def cap(self, code, tz='UTC', **extra):
        env = base_env(self.root, TZ=tz, **extra)
        r = subprocess.run([sys.executable, '-c', PRELUDE + code + '\nprint(json.dumps(out))'], env=env,
                           cwd=self.root, capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            self.fail(f'subprocess failed: {r.stderr[-1500:]}')
        return json.loads(r.stdout.strip().splitlines()[-1])

    def parse(self, lines, tz='UTC'):
        return self.cap("out = [c.parse_line(l) for l in json.loads(os.environ['LINES_JSON'])]",
                        tz=tz, LINES_JSON=json.dumps(lines))


# ---------------------------------------------------------------- A. lutris_env
YML = """name: Game
game:
  env:
    FOO: 'game'
  exe: a.exe
system:
  gpu: card2
  env:
    AFMF_ENABLE: 1
    MANGOHUD_CONFIGFILE: '/old/path.conf'
    ZED: 'z'
  other: x
runner: wine
"""


class LutrisEnv(unittest.TestCase):
    def test_get_env_ignores_game_block_and_reads_values(self):
        self.assertIsNone(lutris_env.get_env(YML, 'FOO'))  # only under game: env:
        self.assertEqual(lutris_env.get_env(YML, 'AFMF_ENABLE'), '1')  # unquoted
        self.assertEqual(lutris_env.get_env(YML, 'ZED'), 'z')  # quotes stripped
        self.assertIsNone(lutris_env.get_env(YML, 'NOPE'))

    def test_get_env_prefix_name_is_not_a_match(self):
        self.assertIsNone(lutris_env.get_env(YML, 'MANGOHUD'))
        self.assertIsNone(lutris_env.get_env(YML, 'AFMF'))

    def test_set_prefix_name_keeps_longer_variable(self):
        out = lutris_env.set_env(YML, 'MANGOHUD', '1')
        self.assertEqual(lutris_env.get_env(out, 'MANGOHUD'), '1')
        self.assertEqual(lutris_env.get_env(out, 'MANGOHUD_CONFIGFILE'), '/old/path.conf')
        self.assertIn("    MANGOHUD: '1'", out.splitlines())
        # and the reverse: setting the long name must not clobber the short one
        out2 = lutris_env.set_env(out, 'MANGOHUD_CONFIGFILE', '/new.conf')
        self.assertEqual(lutris_env.get_env(out2, 'MANGOHUD'), '1')
        self.assertEqual(lutris_env.get_env(out2, 'MANGOHUD_CONFIGFILE'), '/new.conf')

    def test_set_adds_quoted_value_and_touches_nothing_else(self):
        out = lutris_env.set_env(YML, 'NEWVAR', 'v')
        removed = [l for l in out.splitlines() if l not in YML.splitlines()]
        self.assertEqual(removed, ["    NEWVAR: 'v'"])
        rest = [l for l in out.splitlines() if l != "    NEWVAR: 'v'"]
        self.assertEqual(rest, YML.splitlines())  # order of everything else preserved
        self.assertEqual(lutris_env.get_env(out, 'NEWVAR'), 'v')

    def test_set_replaces_existing_instead_of_duplicating(self):
        out = lutris_env.set_env(YML, 'AFMF_ENABLE', '0')  # existing value is unquoted
        lines = out.splitlines()
        self.assertEqual(len([l for l in lines if 'AFMF_ENABLE' in l]), 1)
        self.assertIn("    AFMF_ENABLE: '0'", lines)
        self.assertEqual(len(lines), len(YML.splitlines()))
        self.assertEqual(lines.index("    AFMF_ENABLE: '0'"), YML.splitlines().index('    AFMF_ENABLE: 1'))

    def test_set_variable_that_exists_in_both_blocks_changes_only_system(self):
        out = lutris_env.set_env(YML, 'FOO', 'sys')
        lines = out.splitlines()
        self.assertIn("    FOO: 'game'", lines[:lines.index('system:')])
        self.assertEqual(lutris_env.get_env(out, 'FOO'), 'sys')
        self.assertEqual(lines[:lines.index('system:')], YML.splitlines()[:YML.splitlines().index('system:')])

    def test_system_without_env_gets_env_inside_system(self):
        text = "game:\n  exe: a.exe\nsystem:\n  gpu: card2\nrunner: wine\n"
        out = lutris_env.set_env(text, 'X', '1')
        lines = out.splitlines()
        self.assertIn('  gpu: card2', lines)
        self.assertEqual(lines.count('  env:'), 1)
        i = lines.index('system:')
        j = lines.index('runner: wine')
        self.assertTrue(i < lines.index('  env:') < lines.index("    X: '1'") < j)
        self.assertEqual(lutris_env.get_env(out, 'X'), '1')
        self.assertEqual([l for l in lines if l not in ('  env:', "    X: '1'")], text.splitlines())

    def test_system_not_last_block_insert_stays_inside_system(self):
        text = "system:\n  env:\n    A: 'b'\nrunner: wine\nname: n\n"
        out = lutris_env.set_env(text, 'C', 'd')
        ls = out.splitlines()
        self.assertEqual(ls[:2], ['system:', '  env:'])
        self.assertEqual(sorted(ls[2:4]), ["    A: 'b'", "    C: 'd'"])
        self.assertEqual(ls[4:], ['runner: wine', 'name: n'])

    def test_missing_system_and_no_trailing_newline(self):
        text = "name: a\ngame:\n  exe: x"  # no trailing newline
        out = lutris_env.set_env(text, 'X', '1')
        self.assertEqual(out.splitlines(), ['name: a', 'game:', '  exe: x', 'system:', '  env:', "    X: '1'"])

    def test_env_exists_no_trailing_newline(self):
        text = "system:\n  env:\n    A: 'b'"
        out = lutris_env.set_env(text, 'C', 'd')
        self.assertEqual(sorted(out.splitlines()), sorted(['system:', '  env:', "    A: 'b'", "    C: 'd'"]))
        self.assertEqual(out.splitlines()[:2], ['system:', '  env:'])

    def test_remove_variable(self):
        out = lutris_env.set_env(YML, 'ZED', None)
        self.assertEqual(out.splitlines(), [l for l in YML.splitlines() if 'ZED' not in l])
        self.assertIsNone(lutris_env.get_env(out, 'ZED'))

    def test_remove_does_not_touch_game_block_or_absent(self):
        both = lutris_env.set_env(YML, 'FOO', 'sys')
        out = lutris_env.set_env(both, 'FOO', None)
        self.assertEqual(out, YML)  # game FOO survives, system FOO gone
        self.assertEqual(lutris_env.set_env(YML, 'NOT_THERE', None), YML)
        self.assertEqual(lutris_env.set_env(YML, 'FOO', None), YML)  # only game: has it -> no-op

    def test_remove_does_not_remove_prefixed_neighbour(self):
        out = lutris_env.set_env(YML, 'AFMF', None)
        self.assertEqual(out, YML)
        out = lutris_env.set_env(YML, 'MANGOHUD', None)
        self.assertEqual(out, YML)

    def test_idempotent(self):
        texts = [YML, "name: a\ngame:\n  exe: x", "system:\n  gpu: card2\nrunner: w\n", "system:\n  env:\n    A: 'b'\n"]
        for t in texts:
            for args in (('MANGOHUD', '1'), ('A', 'z'), ('AFMF_ENABLE', '0'), ('MANGOHUD', None)):
                once = lutris_env.set_env(t, *args)
                self.assertEqual(lutris_env.set_env(once, *args), once, (t, args))


# ---------------------------------------------------------------- B1 parse_line
class ParseLine(CapCase):
    CASES = [
        ('[STARTUP] Game Start', {'kind': 'start'}),
        ('[RENDER] Starting device: Vulkan', {'kind': 'renderer', 'value': 'Vulkan'}),
        ('[VULKAN] Present mode = Fifo', {'kind': 'present_mode', 'value': 'Fifo'}),
        ('[VULKAN] Init SwapChain = 2560x1440', {'kind': 'swapchain', 'value': '2560x1440'}),
        ('[STREAMLINE][DLSS] Enabled: true', {'kind': 'upscaler', 'name': 'DLSS', 'value': 'true'}),
        ('[STREAMLINE][NIS] Enabled: false', {'kind': 'upscaler', 'name': 'NIS', 'value': 'false'}),
        ('[STREAMLINE][FSR] Enabled: true', {'kind': 'upscaler', 'name': 'FSR', 'value': 'true'}),
        ('[STREAMLINE][Reflex] Reflex Low Latency: OFF', {'kind': 'reflex', 'value': 'OFF'}),
        ('[SHADER] PSO Cache: Disabled', {'kind': 'pso_cache', 'value': 'Disabled'}),
        (r'Failed to open LMDB environment at C:\users\someone\AppData\x', {'kind': 'lmdb_failed'}),
        ('Generating level 80 area "MapSpiderWoods" with seed 987654321',
         {'kind': 'zone', 'level': 80, 'area': 'MapSpiderWoods'}),
        ('[SCENE] Set Source [Felled Hideout]', {'kind': 'scene', 'name': 'Felled Hideout'}),
        ('[LOADING SCREEN] (Spider Woods) Duration = 1.89286 seconds',
         {'kind': 'loading', 'name': 'Spider Woods', 'seconds': 1.89286}),
        ('[WINDOW] Lost focus', {'kind': 'focus', 'value': 'Lost'}),
        ('[WINDOW] Gained focus', {'kind': 'focus', 'value': 'Gained'}),
        ('Connect time to instance server was 26ms', {'kind': 'connect', 'ms': 26}),
        ('[TEXTURE] Insufficient VRAM', {'kind': 'vram_warning'}),
        ('Closing game gracefully', {'kind': 'exit_graceful'}),
        ('Abnormal disconnect: An unexpected disconnection occurred.', {'kind': 'disconnect'}),
        ('Connected to fra.login.pathofexile2.com in 18ms.', {'kind': 'login_connect'}),
    ]

    def test_every_allowlisted_message_parses_with_trailing_crlf(self):
        res = self.parse([mk_line(m) for m, _ in self.CASES])
        for (msg, want), got in zip(self.CASES, res):
            with self.subTest(msg=msg):
                self.assertIsNotNone(got)
                for k, v in want.items():
                    self.assertEqual(got[k], v)
                    self.assertIs(type(got[k]), type(v))
                self.assertEqual(got['uptime_ms'], 123456)
                self.assertIs(type(got['uptime_ms']), int)

    def test_lf_only_and_no_newline_lines(self):
        res = self.parse([mk_line('[VULKAN] Present mode = Fifo', nl='\n'), mk_line('[VULKAN] Present mode = Fifo', nl='')])
        self.assertEqual([r['value'] for r in res], ['Fifo', 'Fifo'])

    def test_other_levels_work_for_allowlisted(self):
        res = self.parse([mk_line('[TEXTURE] Insufficient VRAM', level=l) for l in ('WARN', 'DEBUG', 'CRIT')])
        self.assertEqual([r['kind'] for r in res], ['vram_warning'] * 3)  # CRIT allowlisted wins over crit

    def test_seed_lmdb_path_are_not_stored(self):
        zone, lmdb = self.parse([mk_line('Generating level 80 area "MapSpiderWoods" with seed 987654321'),
                                 mk_line(r'Failed to open LMDB environment at C:\users\someone\AppData\x')])
        self.assertNotIn('987654321', json.dumps(zone))
        self.assertNotIn('seed', zone)
        self.assertNotIn('someone', json.dumps(lmdb))

    def test_scene_null_and_unknown_are_none(self):
        res = self.parse([mk_line('[SCENE] Set Source [(null)]'), mk_line('[SCENE] Set Source [(unknown)]')])
        self.assertEqual(res, [None, None])

    def test_ip_connect_line_is_none(self):
        res = self.parse([mk_line('Connecting to instance server at 1.2.3.4:21360')])
        self.assertEqual(res, [None])

    def test_chat_lines_are_none_even_with_allowlisted_phrases(self):
        phrases = ['[WINDOW] Lost focus', 'Generating level 80 area "X" with seed 1', 'Closing game gracefully',
                   '[STARTUP] Game Start', 'Connect time to instance server was 26ms', '[TEXTURE] Insufficient VRAM']
        prefixes = ['#SomePlayer: ', '@From Some Player: ', '@To Some Player: ', '$SomePlayer: ', '%SomePlayer: ',
                    '&SomePlayer: ', ': You have entered ']
        lines = [mk_line(p + ph) for p in prefixes for ph in phrases]
        lines.append(mk_line('#SomePlayer: [WINDOW] Lost focus Generating level 80 area "X" with seed 1 Closing game gracefully', up=1))
        res = self.parse(lines)
        self.assertEqual(res, [None] * len(lines))

    def test_message_must_start_at_beginning(self):
        res = self.parse([mk_line('x [WINDOW] Lost focus'), mk_line('Note: Closing game gracefully'),
                          mk_line(' [STARTUP] Game Start x'.strip()[1:] if False else 'the [STARTUP] Game Start')])
        self.assertEqual(res, [None, None, None])

    def test_unlisted_messages_none_at_non_crit_levels(self):
        res = self.parse([mk_line('Something else happened', level=l) for l in ('INFO', 'DEBUG', 'WARN')]
                         + [mk_line('[WINDOW] Resized'), mk_line('[VULKAN] Something')])
        self.assertEqual(res, [None] * 5)

    def test_garbage_lines_are_none_and_do_not_raise(self):
        bad = ['', '\r\n', 'garbage', '2024/07/15 12:34:56', '2024/07/15 12:34:56 123 cffb [INFO Client 4',
               '2024/07/15 12:34:56 abc cffb0719 [INFO Client 416] [STARTUP] Game Start',
               '[INFO Client 416] [STARTUP] Game Start', 'x' * 5000]
        self.assertEqual(self.parse(bad), [None] * len(bad))

    def test_crit_lines(self):
        long_msg = '12 ' + 'a' * 200
        res = self.parse([mk_line('Something went wrong 12 at 345 code 6', level='CRIT'),
                          mk_line('a' * 100, level='CRIT'),
                          mk_line(long_msg, level='CRIT'),
                          mk_line('Connecting to instance server at 1.2.3.4:21360', level='CRIT')])
        self.assertEqual(res[0]['kind'], 'crit')
        self.assertEqual(res[0]['text'], 'Something went wrong N at N code N')
        self.assertEqual(res[1]['text'], 'a' * 60)
        self.assertLessEqual(len(res[2]['text']), 60)
        self.assertNotRegex(res[2]['text'], r'\d')
        self.assertTrue(res[2]['text'].startswith('N a'))
        self.assertEqual(res[3]['kind'], 'crit')
        self.assertNotIn('1.2.3.4', json.dumps(res[3]))
        self.assertNotIn('21360', json.dumps(res[3]))

    def test_timestamp_is_local_time_with_dst(self):
        for stamp, off in (('2024/01/15 12:00:00', 3600), ('2024/07/15 12:00:00', 7200)):
            line = mk_line('[STARTUP] Game Start', stamp=stamp)
            utc = self.parse([line], tz='UTC')[0]['t']
            waw = self.parse([line], tz='Europe/Warsaw')[0]['t']
            y, mo, d = (int(x) for x in stamp[:10].split('/'))
            self.assertEqual(utc, calendar.timegm((y, mo, d, 12, 0, 0)))
            self.assertEqual(utc - waw, off, stamp)


# ---------------------------------------------------------------- B2 log position/read
class ReadEvents(CapCase):
    LINES = {k: mk_line(m, nl='\n') for k, m in {
        'old1': 'Generating level 70 area "OldA" with seed 1', 'old2': 'Generating level 71 area "OldB" with seed 2',
        'start': '[STARTUP] Game Start', 'zone': 'Generating level 80 area "NewZ" with seed 3',
        'filler': 'nothing interesting here',
        'login': 'Connected to fra.login.pathofexile2.com in 18ms.', 'instance': 'Connect time to instance server was 26ms',
        'disc': 'Abnormal disconnect: An unexpected disconnection occurred.'}.items()}
    LINES['crit1'] = mk_line('Bad thing 12 happened', level='CRIT', nl='\n')
    LINES['crit2'] = mk_line('Bad thing 345 happened', level='CRIT', nl='\n')

    def run_snippet(self, code):
        return self.cap("p = os.environ['P']; L = json.loads(os.environ['L'])\n" + code,
                        P=str(self.root / 'Client.txt'), L=json.dumps(self.LINES))

    def test_only_appended_lines_and_crit_counted_not_listed(self):
        out = self.run_snippet("""
open(p, 'w').write(L['old1'] + L['old2'])
size = os.path.getsize(p); ino = os.stat(p).st_ino
pos = c.log_position(p)
open(p, 'a').write(L['start'] + L['crit1'] + L['zone'] + L['crit2'])
ev, cc, tr = c.read_events(pos, p)
out = {'pos': pos, 'size': size, 'ino': ino, 'ev': ev, 'cc': cc, 'tr': tr}
""")
        self.assertEqual(out['pos'], {'offset': out['size'], 'inode': out['ino']})
        self.assertEqual([e['kind'] for e in out['ev']], ['start', 'zone'])
        self.assertEqual(out['ev'][1]['area'], 'NewZ')
        self.assertEqual(out['cc'], {'Bad thing N happened': 2})
        self.assertIs(out['tr'], False)

    def test_disconnect_at_login_is_a_failed_login_not_a_game_disconnect(self):
        # Real order: a wrong password drops the login connection; only a drop after joining an instance counts.
        out = self.run_snippet("""
open(p, 'w').write('')
pos = c.log_position(p)
open(p, 'a').write(L['start'] + L['login'] + L['disc'] + L['login'] + L['instance'] + L['zone'] + L['disc']
                   + L['login'] + L['disc'])
out = [e['kind'] for e in c.read_events(pos, p)[0]]
""")
        self.assertEqual(out, ['start', 'login_connect', 'login_disconnect', 'login_connect', 'connect', 'zone',
                               'disconnect', 'login_connect', 'login_disconnect'])

    def test_truncated_file_is_read_from_start(self):
        out = self.run_snippet("""
open(p, 'w').write(L['old1'] * 5 + L['old2'] * 5)
pos = c.log_position(p)
open(p, 'w').write(L['zone'])   # same inode, smaller
ev, cc, tr = c.read_events(pos, p)
out = {'ev': ev, 'tr': tr}
""")
        self.assertIs(out['tr'], True)
        self.assertEqual([e['area'] for e in out['ev']], ['NewZ'])

    def test_replaced_file_with_larger_size_is_read_from_start(self):
        out = self.run_snippet("""
open(p, 'w').write(L['old1'] + L['old2'])
pos = c.log_position(p)
open(p + '.new', 'w').write(L['zone'] + L['filler'] * 30 + L['start'])
os.replace(p + '.new', p)
ev, cc, tr = c.read_events(pos, p)
out = {'ev': ev, 'tr': tr, 'bigger': os.path.getsize(p) > pos['offset']}
""")
        self.assertTrue(out['bigger'])
        self.assertIs(out['tr'], True)
        self.assertEqual([e['kind'] for e in out['ev']], ['zone', 'start'])  # first line is inside the old offset

    def test_missing_at_read_time(self):
        out = self.run_snippet("""
open(p, 'w').write(L['old1'])
pos = c.log_position(p)
os.remove(p)
out = c.read_events(pos, p)
""")
        self.assertEqual(out, [[], {}, False])

    def test_no_file_at_position_time_then_file_appears(self):
        out = self.run_snippet("""
pos = c.log_position(p)
open(p, 'w').write(L['start'] + L['zone'])
ev, cc, tr = c.read_events(pos, p)
out = {'pos': pos, 'ev': ev, 'tr': tr}
""")
        self.assertEqual(out['pos'], {'offset': 0, 'inode': None})
        self.assertEqual([e['kind'] for e in out['ev']], ['start', 'zone'])
        self.assertIs(out['tr'], False)

    def test_invalid_utf8_does_not_raise(self):
        out = self.run_snippet("""
open(p, 'w').write(L['old1'])
pos = c.log_position(p)
with open(p, 'ab') as f:
    f.write(b'\\xff\\xfe\\x80 garbage \\xc3\\x28\\n')
    f.write(L['zone'].encode())
    f.write(('2024/07/15 12:34:56 1 cffb0719 [INFO Client 416] [VULKAN] Present mode = F\\xe9\\xff\\n').encode('latin-1'))
ev, cc, tr = c.read_events(pos, p)
out = {'kinds': [e['kind'] for e in ev], 'tr': tr}
""")
        self.assertIn('zone', out['kinds'])
        self.assertIs(out['tr'], False)


# ---------------------------------------------------------------- B3 frame_log_info
SYS_HEAD = ("v1\nv0.8.4\n---------------------SYSTEM INFO---------------------\n"
            "os,cpu,gpu,ram,kernel,driver,cpuscheduler\n"
            "EndeavourOS,{cpu},NVIDIA GeForce RTX 5070 Ti,63125992,7.3.4-arch1-1,,powersave\n"
            "--------------------FRAME METRICS--------------------\n")
COLS = ("fps,frametime,cpu_load,cpu_power,gpu_load,cpu_temp,gpu_temp,gpu_core_clock,gpu_mem_clock,"
        "gpu_vram_used,gpu_power,ram_used,swap_used,process_rss,cpu_mhz,elapsed\n")


def csv_text(n, step_ns=100_000_000, cpu='AMD Ryzen 7 9800X3D 8-Core Processor', head=True):
    h = SYS_HEAD.format(cpu=cpu) + COLS if head else ''
    return h + ''.join(f'241.236,4.14531,19.083,0,6,42,0,0,0,0,0,36.8334,0.468723,0,5243,{(i + 1) * step_ns}\n'
                       for i in range(n))


class FrameLogInfo(CapCase):
    def info(self, data, name='f.csv', gz=False):
        p = self.root / name
        if gz:
            with gzip.open(p, 'wb') as f:
                f.write(data.encode())
        else:
            p.write_text(data)
        return self.cap("out = c.frame_log_info(os.environ['P'])", P=str(p))

    def test_rows_and_seconds_plain_and_gz(self):
        for gz in (False, True):
            r = self.info(csv_text(7, 500_000_000), 'f.csv.gz' if gz else 'f.csv', gz)
            self.assertEqual(r[0], 7)
            self.assertAlmostEqual(r[1], 3.5, places=6)

    def test_no_rows_empty_and_missing(self):
        self.assertEqual(self.info(csv_text(0)), [0, 0.0])
        self.assertEqual(self.info(''), [0, 0.0])
        self.assertEqual(self.cap("out = c.frame_log_info(os.environ['P'])", P=str(self.root / 'nope.csv')), [0, 0.0])

    def test_comma_in_cpu_name_does_not_change_result(self):
        a = self.info(csv_text(5))
        b = self.info(csv_text(5, cpu='AMD, Ryzen 7, Special'))
        self.assertEqual(a, b)
        self.assertEqual(a[0], 5)

    def test_last_line_cut_mid_write(self):
        r = self.info(csv_text(6) + '240.1,4.1')
        self.assertEqual(r[0], 6)
        self.assertAlmostEqual(r[1], 0.6, places=6)

    def test_layout_without_v1_and_dashes(self):
        text = ("os,cpu,gpu,ram,kernel,driver,cpuscheduler\nEndeavourOS,AMD,NVIDIA,1,7.3,,powersave\n" + COLS)
        text += csv_text(4, 250_000_000, head=False)
        r = self.info(text)
        self.assertEqual(r[0], 4)
        self.assertAlmostEqual(r[1], 1.0, places=6)


# ---------------------------------------------------------------- B4 find_game / alive
class FindGame(CapCase):
    def proc(self, pid, cmd='C:\\\\Games\\\\PathOfExile.exe', comm='PathOfExile.exe', rss=None, exe=None, cmdline=True):
        d = self.root / 'proc' / str(pid)
        d.mkdir(parents=True, exist_ok=True)
        if comm is not None:
            (d / 'comm').write_text(comm + '\n')
        if rss is not None:
            (d / 'status').write_text(f'Name:\t{comm}\nVmRSS:\t{rss:>9} kB\nThreads:\t3\n')
        if exe:
            os.symlink(exe, d / 'exe')
        if cmdline:
            (d / 'cmdline').write_bytes(cmd.replace('\\\\', '\\').encode() + b'\0--arg\0')

    def find(self, **extra):
        (self.root / 'proc').mkdir(exist_ok=True)
        return self.cap("out = c.find_game()", **extra)

    def test_none_when_empty_or_missing_root(self):
        self.assertIsNone(self.find())
        shutil.rmtree(self.root / 'proc')
        self.assertIsNone(self.cap("out = c.find_game()"))

    def test_launch_wrappers_with_exe_in_args_do_not_count(self):
        for i, comm in enumerate(['lutris-wrapper', 'python3', 'umu-run', 'bash']):
            self.proc(100 + i, comm=comm, rss=999999, exe='/usr/bin/' + comm)
        self.assertIsNone(self.find())

    def test_game_by_comm(self):
        self.proc(200, rss=100)
        self.assertEqual(self.find(), 200)

    def test_game_by_wine_exe_symlink_with_other_comm(self):
        self.proc(300, comm='wine64-preloader', rss=100, exe='/opt/wine/bin/wine64-preloader')
        self.assertEqual(self.find(), 300)

    def test_wrapper_with_wine_exe_is_not_confused_with_python_exe(self):
        self.proc(310, comm='some-launcher', rss=500, exe='/usr/bin/python3.12')
        self.assertIsNone(self.find())

    def test_non_matching_cmdline_does_not_count_even_for_wine(self):
        self.proc(320, cmd='C:\\\\Windows\\\\notepad.exe', comm='wine64-preloader', rss=100, exe='/usr/bin/wine64-preloader')
        self.assertIsNone(self.find())

    def test_largest_rss_wins_numerically(self):
        self.proc(100, rss=99999)
        self.proc(200, rss=100000)  # larger as a number, smaller as a string
        self.proc(300, rss=9)
        self.assertEqual(self.find(), 200)

    def test_noise_entries_and_vanished_process_do_not_crash(self):
        (self.root / 'proc' / 'self').mkdir(parents=True)
        (self.root / 'proc').joinpath('stat').write_text('cpu 1\n')
        self.proc(400, comm=None, rss=1, cmdline=True)  # comm vanished
        (self.root / 'proc' / '401').mkdir()  # empty, vanished
        self.proc(402, rss=5)
        self.assertEqual(self.find(), 402)

    def test_game_preferred_over_wine_helper_even_with_larger_rss(self):
        self.proc(100, comm='steam.exe', rss=900000, exe='/opt/wine/bin/wine64')  # Proton helper started first
        self.proc(200, rss=100)
        self.assertEqual(self.find(), 200)

    def test_game_preferred_over_helper_with_higher_pid(self):
        self.proc(100, rss=100)
        self.proc(300, comm='steam.exe', rss=900000, exe='/opt/wine/bin/wine64')
        self.assertEqual(self.find(), 100)

    def test_helper_alone_is_returned_so_sampling_can_begin(self):
        self.proc(100, comm='steam.exe', rss=900000, exe='/opt/wine/bin/wine64')
        self.assertEqual(self.find(), 100)

    def test_custom_regex(self):
        self.proc(500, cmd='C:\\\\x\\\\MyGame.exe', comm='wine64-preloader', rss=1, exe='/usr/bin/wine64-preloader')
        self.assertEqual(self.find(GAMELOG_PROC_RE=r'MyGame\.exe'), 500)
        self.assertIsNone(self.find())  # default regex does not match

    def test_alive(self):
        stats = {1: '1 (PathOfExile.exe) S 1 1 1 0', 2: '2 (a b) Z 1 1 1', 3: '3 (x) X 1 1 1', 4: '4 (x) R 1',
                 5: '5 (we ird) Z x) S 1 1 1', 6: '6 (a b) Z 1', 8: '8 (x) D 1'}
        for pid, s in stats.items():
            d = self.root / 'proc' / str(pid)
            d.mkdir(parents=True)
            (d / 'stat').write_text(s + '\n')
        out = self.cap("out = {p: c.alive(p) for p in (1,2,3,4,5,6,7,8,99)}")
        self.assertEqual(out, {'1': True, '2': False, '3': False, '4': True, '5': True, '6': False, '7': False,
                               '8': True, '99': False})


# ---------------------------------------------------------------- B5 CLI + record scenarios
MARKERS = ['MARKERCRED1', 'MARKERTOKEN2', 'MARKERAPIKEY3', 'MARKERACCT4', 'MARKERLOGIN5', 'MARKERCHAT6',
           'MARKERHOME7', 'MARKERUSER8', 'MARKERMAILENV9', 'MARKERPASS10', 'MARKERMAILINI11', 'MARKERJUNK12',
           '203.0.113.7']

FAKEGAME = '''#!/usr/bin/env python3
import json, os, time
E = os.environ
ops = json.load(open(E['SCENARIO']))
proc, log = E['GAMELOG_PROC'], E['GAMELOG_CLIENT_LOG']
inc = os.path.join(E['GAMELOG_STATE'], 'incoming')
def put(p, s, m='w', nl=None):
    with open(p, m, newline=nl) as f:
        f.write(s.replace('{TS}', time.strftime('%Y/%m/%d %H:%M:%S')))
def stat(pid, comm):
    return f"{pid} ({comm}) S 1 1 1 0 -1 4194304 100 0 0 0 200 100 0 0 20 0 5 0 5000 1000000 5000 " + " ".join(["0"] * 30) + "\\n"
for op in ops:
    k = op[0]
    if k == 'proc':
        pid, env = str(op[1]), op[2]
        d = os.path.join(proc, pid)
        os.makedirs(os.path.join(d, 'task', pid), exist_ok=True)
        os.makedirs(os.path.join(d, 'fd'), exist_ok=True)
        put(os.path.join(d, 'comm'), 'PathOfExile.exe\\n')
        put(os.path.join(d, 'stat'), stat(pid, 'PathOfExile.exe'))
        put(os.path.join(d, 'task', pid, 'stat'), stat(pid, 'PathOfExile.exe'))
        put(os.path.join(d, 'status'), 'Name:\\tPathOfExile.exe\\nVmRSS:\\t  500000 kB\\nThreads:\\t5\\n')
        put(os.path.join(d, 'environ'), ''.join(f'{a}={b}\\0' for a, b in env.items()))
        put(os.path.join(d, 'maps'), '')
        put(os.path.join(d, 'io'), 'rchar: 1\\nwchar: 2\\nread_bytes: 3\\nwrite_bytes: 4\\n')
        put(os.path.join(d, 'cmdline'), 'C:\\\\Games\\\\PathOfExile.exe\\0--arg\\0')
        if op[3]:
            put(os.path.join(proc, 'stat'), 'cpu  100 0 100 1000 0 0 0 0 0 0\\n')
            put(os.path.join(proc, 'meminfo'), 'MemTotal: 1000 kB\\nMemAvailable: 500 kB\\n')
            os.makedirs(os.path.join(proc, 'pressure'), exist_ok=True)
            for n in ('cpu', 'memory', 'io'):
                put(os.path.join(proc, 'pressure', n), 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\\n')
    elif k == 'rmproc':
        import shutil
        shutil.rmtree(os.path.join(proc, str(op[1])), ignore_errors=True)
    elif k == 'sleep':
        time.sleep(op[1])
    elif k == 'append':
        put(log, op[1], 'a', nl='')
    elif k == 'truncate':
        put(log, op[1], 'w', nl='')
    elif k == 'replace':
        put(log + '.new', op[1], 'w', nl='')
        os.replace(log + '.new', log)
    elif k == 'csv':
        os.makedirs(inc, exist_ok=True)
        put(os.path.join(inc, op[1].replace('{TSFILE}', time.strftime('%Y-%m-%d_%H-%M-%S', time.localtime(time.time() - 1.5)))), op[2])
'''


def L(msg, level='INFO', up=1000):
    return f'{{TS}} {up} cffb0719 [{level} Client 416] {msg}\r\n'  # stamped when written


GAME_ENV = {'PROTON_LOG': '1', 'WINEDEBUG': '-all', 'MANGOHUD': '1', 'PROTON_SECRET_TOKEN': 'MARKERTOKEN2',
            'STEAM_API_KEY': 'MARKERAPIKEY3', 'HOME': '/home/MARKERHOME7', 'USER': 'MARKERUSER8',
            'MAIL': '/var/mail/MARKERMAILENV9', 'MY_PRIVATE_THING': 'MARKERJUNK12', 'PATH': '/usr/bin'}
INI = ('[DISPLAY]\nrenderer_type=Vulkan\nvsync=Off\naccount_name=MARKERACCT4\nlogin_token=MARKERLOGIN5\n'
       'user_email=MARKERMAILINI11@example.com\npassword=MARKERPASS10\n')


class Sim:
    """One isolated record run: own root, stubs and fake proc; started in a thread."""

    def __init__(self, base, name, ops, launch=True, nvidia='ok', pre_log='', stale=False, full=False, **env):
        self.name = name
        self.root = Path(base) / name
        r = self.root
        for d in ('state', 'proc', 'sys', 'game', 'bin', 'home', 'lutris', 'xdg-run', 'xdg-state', 'xdg-config'):
            (r / d).mkdir(parents=True)
        (r / 'game' / 'Client.txt').write_text(pre_log.replace('{TS}', time.strftime('%Y/%m/%d %H:%M:%S')))
        (r / 'game' / 'production_Config.ini').write_text(INI)
        (r / 'game' / 'poe2_production_login.credentials').write_text('MARKERCRED1\n')
        self.launch = launch
        self.nvidia = nvidia
        self.full = full
        self.env_over = env
        for op in ops:
            if op[0] == 'proc':
                op.append(full)
        (r / 'scenario.json').write_text(json.dumps(ops))
        self.exe('fakegame.py', FAKEGAME)
        self.exe('bin/notify', '#!/bin/bash\nprintf \'%s\\x1f\' "$@" >> "$NOTIFY_LOG"\nprintf \'\\n\' >> "$NOTIFY_LOG"\n')
        self.exe('bin/nvidia-smi', f'''#!/bin/bash
case "$*" in
*-lms*) echo $$ >> "$NV_PIDS"
  if [[ "$NV_MODE" == hang ]]; then exec sleep 600; fi
  while :; do echo "9001,9002,9003,9004,9005,9006,9007,9008,9009,9010,9011,9012,9013,9014"; sleep 0.1; done;;
*driver_version*) [[ "$NV_MODE" == hang ]] || echo "580.95, 1000 MiB, 16303 MiB";;
*compute-apps*) [[ "$NV_MODE" == hang ]] || echo "4242, 900 MiB";;
esac
''')
        self.exe('bin/powerprofilesctl', '#!/bin/bash\n[[ "$1" == get ]] && echo performance\nexit 0\n')
        self.exe('bin/pacman', '#!/bin/bash\necho "pkg 1.0-1"\n')
        for t in ('ss', 'journalctl', 'kreadconfig6'):
            self.exe('bin/' + t, '#!/bin/bash\nexit 0\n')
        if stale:
            inc = r / 'state' / 'incoming'
            inc.mkdir()
            for n, body in (('PathOfExile.exe_2020-01-01_00-00-00.csv', csv_text(50, cpu='STALECPUMARK')),
                            ('PathOfExile.exe_2020-01-01_00-00-00_summary.csv', 'STALESUMMARY\n')):
                (inc / n).write_text(body)
                os.utime(inc / n, (time.time() - 86400, time.time() - 86400))
        self.rc = self.out = self.err = None
        self.elapsed = None

    def exe(self, rel, text):
        p = self.root / rel
        p.write_text(text)
        p.chmod(0o755)

    def env(self):
        r = self.root
        opts = dict(GAMELOG_NOTIFY=r / 'bin/notify', GAMELOG_LAUNCH=r / 'fakegame.py',
                    PATH=f'{r}/bin:{REAL_PATH}', SCENARIO=r / 'scenario.json', NOTIFY_LOG=r / 'notify.log',
                    NV_PIDS=r / 'nvpids', NV_MODE=self.nvidia)
        opts.update(self.env_over)
        return base_env(r, **opts)

    def _run(self):
        e = self.env()
        t0 = time.time()
        game = None
        args = [GAMELOG, 'record'] + (['--launch'] if self.launch else [])
        try:
            if not self.launch:
                game = subprocess.Popen([str(self.root / 'fakegame.py')], env=e, cwd=self.root)
            p = subprocess.Popen(args, env=e, cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.out, self.err = p.communicate(timeout=40)
                self.rc = p.returncode
            except subprocess.TimeoutExpired:
                p.kill()
                self.out, self.err = p.communicate()
                self.rc = 'timeout'
        finally:
            if game:
                try:
                    game.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    game.kill()
        self.elapsed = time.time() - t0

    def start(self):
        self.th = threading.Thread(target=self._run)
        self.th.start()

    def finish(self):
        self.th.join()

    def sessions(self):
        d = self.root / 'state' / 'sessions'
        return sorted(d.iterdir()) if d.is_dir() else []

    def session(self):
        s = self.sessions()
        assert len(s) == 1, f'{self.name}: expected one session, got {s}; rc={self.rc} err={self.err}'
        return s[0]

    def meta(self):
        return json.loads((self.session() / 'meta.json').read_text())

    def notes(self):
        p = self.root / 'notify.log'
        if not p.exists():
            return []
        return [x.split('\x1f')[:-1] for x in p.read_text().split('\n') if x]

    def prio4(self):
        out = []
        for n in self.notes():
            if '--priority' in n and n[n.index('--priority') + 1] == '4':
                out.append(n)
        return out

    def kill_stubs(self):
        p = self.root / 'nvpids'
        if p.exists():
            for pid in p.read_text().split():
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except (ProcessLookupError, ValueError):
                    pass


def tree_blobs(root):
    for dp, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(dp, f)
            data = Path(p).read_bytes()
            yield p, data
            if f.endswith('.gz'):
                try:
                    yield p + '[gunzipped]', gzip.decompress(data)
                except OSError:
                    pass


class Sessions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='gamelog-sim.')
        cls.addClassCleanup(shutil.rmtree, cls.tmp, True)
        pid = 4242
        game = [['proc', pid, GAME_ENV]]
        good = csv_text(15)  # 1.5 s, 15 frames; written at the end of play, like MangoHud's last flush
        S = cls.S = {}
        chat = ''.join(L(p + ph) for p in ('#Spammer: MARKERCHAT6 ', '@From Spammer: MARKERCHAT6 ', '@To Spammer: MARKERCHAT6 ',
                                           '$Spammer: MARKERCHAT6 ', '%Spammer: MARKERCHAT6 ', '&Spammer: MARKERCHAT6 ',
                                           ': You have entered MARKERCHAT6 ')
                       for ph in ('Generating level 99 area "ChatZone" with seed 5 Closing game gracefully',
                                  '[STARTUP] Game Start [WINDOW] Lost focus'))
        pre = L('Generating level 70 area "OldArea" with seed 1') + L('[STARTUP] Game Start')
        S['ok'] = Sim(cls.tmp, 'ok', game + [
            ['append', L('[STARTUP] Game Start') + L('[RENDER] Starting device: Vulkan')
             + L('Generating level 80 area "MapSpiderWoods" with seed 987654321') + chat
             + L('Connecting to instance server at 203.0.113.7:21360')
             + L('Something bad 12 at 345', 'CRIT') + L('Something bad 77 at 1', 'CRIT')],
            ['sleep', 1.8], ['append', L('Connect time to instance server was 26ms') + L('Closing game gracefully')],
            ['csv', 'PathOfExile.exe_{TSFILE}.csv', good],
            ['csv', 'PathOfExile.exe_{TSFILE}_summary.csv', 'SUMMARY\n'],
            ['rmproc', pid]], pre_log=pre, stale=True, full=True)
        S['nvhang'] = Sim(cls.tmp, 'nvhang', game + [['sleep', 1.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', good], ['rmproc', pid]], nvidia='hang')
        started = [['append', L('[STARTUP] Game Start')]]
        S['noframes_missing'] = Sim(cls.tmp, 'nfm', game + started + [['sleep', 1.5], ['rmproc', pid]])
        S['noframes_zero'] = Sim(cls.tmp, 'nfz', game + started + [['sleep', 1.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', csv_text(0)], ['rmproc', pid]])
        # After a patch the game can sit for the whole session without ever logging its start.
        S['stuck'] = Sim(cls.tmp, 'stuck', game + [['append', L('Started patching (1 free bytes available)')],
                                                   ['sleep', 1.5], ['rmproc', pid]])
        S['short'] = Sim(cls.tmp, 'short', game + [['sleep', 1.2], ['rmproc', pid]], GAMELOG_MIN_SECONDS='5')
        S['short_no_notifier'] = Sim(cls.tmp, 'short_no_notifier', game + [['sleep', 1.2], ['rmproc', pid]],
                                     GAMELOG_MIN_SECONDS='5', GAMELOG_NOTIFY='/nonexistent/notify-command')
        S['nogame'] = Sim(cls.tmp, 'nogame', [], GAMELOG_START_WAIT='1', GAMELOG_LAUNCH='/bin/true')
        S['crash'] = Sim(cls.tmp, 'crash', game + [
            ['append', L('[STARTUP] Game Start')],
            ['sleep', 1.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', csv_text(15) + '240.1,4.1'], ['rmproc', pid]])
        S['graceful_before_start'] = Sim(cls.tmp, 'gbs', game + [
            ['append', L('[STARTUP] Game Start') + L('Closing game gracefully') + L('[STARTUP] Game Start')],
            ['sleep', 1.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', good], ['rmproc', pid]])
        S['truncate'] = Sim(cls.tmp, 'trunc', game + [
            ['append', L('[STARTUP] Game Start')], ['sleep', 0.6],
            ['truncate', L('Generating level 80 area "AfterRot" with seed 1') + L('[STARTUP] Game Start')
             + L('Closing game gracefully')],
            ['sleep', 1.2], ['csv', 'PathOfExile.exe_{TSFILE}.csv', good], ['rmproc', pid]],
            pre_log=''.join(L('filler line number %d with padding padding padding' % i) for i in range(40)))
        S['replace'] = Sim(cls.tmp, 'repl', game + [
            ['sleep', 0.5],
            ['replace', L('Generating level 80 area "AfterReplace" with seed 1')
             + ''.join(L('filler %d with some more padding to grow the file' % i) for i in range(60))],
            ['sleep', 1.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', good], ['rmproc', pid]],
            pre_log=L('Generating level 70 area "OldArea" with seed 1') + L('x'))
        S['restart'] = Sim(cls.tmp, 'restart', [['proc', 4242, GAME_ENV], ['sleep', 0.8],
                                                ['rmproc', 4242], ['sleep', 0.3], ['proc', 4343, GAME_ENV],
                                                ['sleep', 0.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', csv_text(10)], ['rmproc', 4343]])
        S['nolaunch'] = Sim(cls.tmp, 'nolaunch', game + [['sleep', 1.8], ['csv', 'PathOfExile.exe_{TSFILE}.csv', good], ['rmproc', pid]], launch=False)
        for s in S.values():
            cls.addClassCleanup(s.kill_stubs)
        for s in S.values():
            s.start()
        for s in S.values():
            s.finish()

    # ---- control scenario
    def test_ok_session_status_exit_and_no_alert(self):
        s = self.S['ok']
        self.assertEqual(s.rc, 0, s.err)
        m = s.meta()
        self.assertEqual(m['status'], 'ok')
        self.assertEqual(m['exit'], 'graceful')
        self.assertEqual(m['frames'], 15)
        self.assertAlmostEqual(m['frame_seconds'], 1.5, places=3)
        for k in ('start', 'end', 'game_start', 'samples', 'log_truncated', 'crit_counts', 'settings', 'process'):
            self.assertIn(k, m)
        self.assertIs(m['log_truncated'], False)
        self.assertIsInstance(m['settings'], dict)
        self.assertEqual(s.prio4(), [])
        self.assertIn(str(s.session()), s.out)

    def test_ok_events_only_session_lines_chat_and_ip_excluded(self):
        s = self.S['ok']
        ev = [json.loads(x) for x in (s.session() / 'events.jsonl').read_text().splitlines() if x]
        self.assertEqual([e['kind'] for e in ev], ['start', 'renderer', 'zone', 'connect', 'exit_graceful'])
        self.assertEqual(ev[2]['area'], 'MapSpiderWoods')  # not OldArea (before the session), not ChatZone

    def test_ok_crit_counted_in_meta_not_events(self):
        m = self.S['ok'].meta()
        self.assertEqual(m['crit_counts'], {'Something bad N at N': 2})

    def test_ok_sampler_csv_shape(self):
        rows = (self.S['ok'].session() / 'sampler.csv').read_text().splitlines()
        hdr = rows[0].split(',')
        self.assertEqual(hdr[:2], ['t', 'pid'])
        self.assertGreaterEqual(len(rows), 4)
        for r in rows[1:]:
            cells = r.split(',')
            self.assertEqual(len(cells), len(hdr))
            self.assertEqual(cells[1], '4242')
            self.assertGreater(float(cells[0]), 1e9)

    def test_ok_gpu_columns_filled_from_stream(self):
        rows = (self.S['ok'].session() / 'sampler.csv').read_text().splitlines()
        cells = [r.split(',') for r in rows[1:]]
        cols = [i for i in range(len(cells[0])) if any(r[i].startswith('900') or r[i].startswith('901') for r in cells)]
        self.assertTrue(cols, 'no sampler column carries the nvidia-smi stream values 9001..9014')

    def test_session_dir_is_private(self):
        self.assertEqual(self.S['ok'].session().stat().st_mode & 0o777, 0o700)

    def test_frames_moved_stale_and_summary_deleted(self):
        s = self.S['ok']
        frames = sorted(p.name for p in (s.session() / 'frames').iterdir())
        self.assertEqual(len(frames), 1, frames)
        self.assertTrue(frames[0].endswith('.csv.gz'))
        text = gzip.decompress((s.session() / 'frames' / frames[0]).read_bytes()).decode()
        self.assertEqual(text, csv_text(15))
        inc = s.root / 'state' / 'incoming'
        left = [p.name for p in inc.iterdir()] if inc.exists() else []
        self.assertEqual(left, [])
        for p, data in tree_blobs(s.session()):
            self.assertNotIn(b'STALE', data, p)

    def test_privacy_no_marker_anywhere_in_session_tree(self):
        s = self.S['ok']
        hits = [(p, m) for p, data in tree_blobs(s.session()) for m in MARKERS if m.encode() in data]
        self.assertEqual(hits, [])

    def test_config_ini_keeps_plain_keys_drops_secret_ones(self):
        text = (self.S['ok'].session() / 'config.ini').read_text()
        self.assertIn('renderer_type=Vulkan', text)
        self.assertIn('vsync=Off', text)
        for key in ('account_name', 'login_token', 'user_email', 'password'):
            self.assertNotIn(key, text)

    def test_process_env_has_gaming_vars(self):
        env = self.S['ok'].meta()['process']['env']
        self.assertEqual(env.get('PROTON_LOG'), '1')

    # ---- alerts
    def test_missing_frame_log_raises_no_frames_alert(self):
        for key in ('noframes_missing', 'noframes_zero'):
            s = self.S[key]
            with self.subTest(key):
                self.assertEqual(s.rc, 0, s.err)
                self.assertEqual(s.meta()['status'], 'no-frames')
                alerts = [n for n in s.prio4() if any('mangohud' in a.lower() for a in n)]
                self.assertEqual(len(alerts), 1, s.notes())

    def test_game_that_never_started_is_not_blamed_on_mangohud(self):
        s = self.S['stuck']
        self.assertEqual(s.rc, 0, s.err)
        self.assertEqual(s.meta()['status'], 'not-started')
        alerts = s.prio4()
        self.assertEqual(len(alerts), 1, s.notes())
        text = ' '.join(alerts[0]).lower()
        self.assertNotIn('mangohud', text)
        self.assertIn('never finished starting', text)

    def test_short_session(self):
        s = self.S['short']
        self.assertEqual(s.meta()['status'], 'short')
        self.assertTrue(any('short' in ' '.join(n).lower() for n in s.notes()), s.notes())
        self.assertEqual([n for n in s.prio4() if any('mangohud' in a.lower() for a in n)], [])

    def test_a_missing_notifier_does_not_cost_the_session_its_metadata(self):
        s = self.S['short_no_notifier']
        self.assertEqual(s.meta()['status'], 'short')
        self.assertNotIn('Traceback', s.err)

    def test_game_never_appears(self):
        s = self.S['nogame']
        self.assertEqual(s.rc, 1, s.err)
        self.assertGreaterEqual(len(s.notes()), 1)
        self.assertEqual(s.meta()['status'], 'no-game')

    # ---- crash / graceful
    def test_crash_with_cut_csv_row_completes(self):
        s = self.S['crash']
        self.assertEqual(s.rc, 0, s.err)
        m = s.meta()
        self.assertEqual(m['frames'], 15)
        self.assertEqual(m['exit'], 'not graceful')

    def test_graceful_line_before_last_start_is_not_graceful(self):
        self.assertEqual(self.S['graceful_before_start'].meta()['exit'], 'not graceful')

    # ---- log rotation
    def test_truncated_log_events_recorded(self):
        s = self.S['truncate']
        m = s.meta()
        self.assertIs(m['log_truncated'], True)
        ev = [json.loads(x) for x in (s.session() / 'events.jsonl').read_text().splitlines() if x]
        self.assertIn('AfterRot', [e.get('area') for e in ev])
        self.assertEqual(m['exit'], 'graceful')

    def test_replaced_log_events_recorded(self):
        s = self.S['replace']
        self.assertIs(s.meta()['log_truncated'], True)
        ev = [json.loads(x) for x in (s.session() / 'events.jsonl').read_text().splitlines() if x]
        self.assertEqual([e.get('area') for e in ev if e['kind'] == 'zone'], ['AfterReplace'])

    # ---- robustness
    def test_hanging_nvidia_smi_does_not_block_and_leaves_gpu_columns_empty(self):
        s, ok = self.S['nvhang'], self.S['ok']
        self.assertEqual(s.rc, 0, s.err)
        self.assertLess(s.elapsed, ok.elapsed + 3)
        rows = [r.split(',') for r in (s.session() / 'sampler.csv').read_text().splitlines()]
        hdr = rows[0]
        self.assertGreaterEqual(len(rows), 4)
        for i, h in enumerate(hdr):
            if 'gpu' in h.lower() or 'vram' in h.lower():
                self.assertEqual({r[i] for r in rows[1:]}, {''}, h)
        self.assertEqual(s.meta()['status'], 'ok')

    def test_process_restart_is_one_session_with_both_pids(self):
        s = self.S['restart']
        self.assertEqual(s.rc, 0, s.err)
        self.assertEqual(len(s.sessions()), 1)
        rows = (s.session() / 'sampler.csv').read_text().splitlines()[1:]
        pids = {r.split(',')[1] for r in rows}
        self.assertTrue({'4242', '4343'} <= pids, pids)

    def test_record_without_launch(self):
        s = self.S['nolaunch']
        self.assertEqual(s.rc, 0, s.err)
        self.assertEqual(s.meta()['status'], 'ok')
        self.assertIn(str(s.session()), s.out)


# ---------------------------------------------------------------- B6 helper, patient start, failure isolation, config, proton
FAKE2 = r'''#!/usr/bin/env python3
import json, os, shutil, time
E = os.environ
ops = json.load(open(E['SCENARIO']))
proc = E['GAMELOG_PROC']
def put(p, s):
    with open(p, 'w') as f:
        f.write(s)
def stat(pid, comm):
    return f"{pid} ({comm}) S 1 1 1 0 -1 4194304 100 0 0 0 200 100 0 0 20 0 5 0 5000 1000000 5000 " + " ".join(["0"] * 30) + "\n"
for op in ops:
    k = op[0]
    if k == 'xproc':
        pid, o = str(op[1]), op[2]
        comm = o.get('comm', 'PathOfExile.exe')
        d = os.path.join(proc, pid)
        os.makedirs(os.path.join(d, 'task', pid), exist_ok=True)
        os.makedirs(os.path.join(d, 'fd'), exist_ok=True)
        put(os.path.join(d, 'status'), f"Name:\t{comm}\nVmRSS:\t  {o.get('rss', 500000)} kB\nThreads:\t5\n")
        put(os.path.join(d, 'environ'), ''.join(f'{a}={b}\0' for a, b in o.get('env', {}).items()))
        put(os.path.join(d, 'maps'), o.get('maps', ''))
        put(os.path.join(d, 'io'), 'rchar: 1\nwchar: 2\nread_bytes: 3\nwrite_bytes: 4\n')
        put(os.path.join(d, 'cmdline'), '\0'.join(o.get('cmd', ['C:\\Games\\PathOfExile.exe', '--arg'])) + '\0')
        if o.get('exe'):
            os.symlink(o['exe'], os.path.join(d, 'exe'))
        put(os.path.join(d, 'task', pid, 'stat'), stat(pid, comm))
        put(os.path.join(d, 'stat'), stat(pid, comm))
        put(os.path.join(d, 'comm'), comm + '\n')
    elif k == 'rmproc':
        shutil.rmtree(os.path.join(proc, str(op[1])), ignore_errors=True)
    elif k == 'sleep':
        time.sleep(op[1])
    elif k == 'mark':
        put(os.path.join(E['MARKDIR'], op[1]), repr(time.time()))
'''

HELPER = {'comm': 'steam.exe', 'exe': '/opt/wine/bin/wine64', 'rss': 900000,
          'cmd': ['C:\\windows\\system32\\steam.exe', 'C:\\Games\\PathOfExile.exe']}
LAUNCHER_LUTRIS = {'comm': 'lutris-wrapper', 'exe': '/usr/bin/python3', 'rss': 1000,
                   'cmd': ['lutris-wrapper: Path of Exile 2']}
LAUNCHER_UMU = {'comm': 'umu-run', 'exe': '/usr/bin/python3', 'rss': 1000,
                'cmd': ['umu-run', 'C:\\Games\\PathOfExile.exe']}
GAME_PROC = {'env': GAME_ENV, 'rss': 100000}
CONFIG_INI = ('[DISPLAY]\nrenderer_type=Vulkan\nvsync=Off\nlogin_token=MARKDISPTOKEN\n'
              '[LOGIN]\ngateway_id=xyzMARK\nrealm=harmlessrealm\n'
              '[UI]\nui_scale=1.5\n'
              '[NETWORKING]\nnetworking_type=predictive\n'
              '[ACTION_KEYS]\nkey_inventory=i\n'
              '[GENERAL]\nengine_multithreading_mode=enabled\npassword=MARKGENPASS\n'
              '[CACHED_DATA]\nlast_zone=MARKZONE\n'
              '[SOUND]\nmaster_volume=50\n')
FLAT_INI = 'renderer_type=Vulkan\nvsync=Off\npassword=MARKFLATPASS\nsome_plain_key=3\n'


class Sim2(Sim):
    """Sim with a scripted launch stub (own op set, output detached) and exact start/end times."""

    def __init__(self, base, name, ops, timeout=40, **env):
        super().__init__(base, name, ops, **env)
        self.timeout = timeout
        self.exe('fakegame.py', FAKE2)
        self.exe('launch.sh', f'#!/bin/bash\nexec >/dev/null 2>&1\nexec {sys.executable} {self.root}/fakegame.py\n')
        self.env_over.setdefault('GAMELOG_LAUNCH', self.root / 'launch.sh')
        self.env_over['MARKDIR'] = self.root
        self.t_end = None

    def mark(self, name):
        p = self.root / name
        return float(p.read_text()) if p.exists() else None

    def _run(self):
        t0 = time.time()
        p = subprocess.Popen([GAMELOG, 'record', '--launch'], env=self.env(), cwd=self.root,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.out, self.err = p.communicate(timeout=self.timeout)
            self.rc = p.returncode
        except subprocess.TimeoutExpired:
            p.kill()
            self.out, self.err = p.communicate()
            self.rc = 'timeout'
        self.t_end = time.time()
        self.elapsed = self.t_end - t0


def write_proc(root, pid, comm, cmd):
    d = Path(root) / 'proc' / str(pid)
    d.mkdir(parents=True)
    (d / 'comm').write_text(comm + '\n')
    (d / 'cmdline').write_bytes('\0'.join(cmd).encode() + b'\0')
    (d / 'stat').write_text(f'{pid} ({comm}) S 1 1 1 0\n')


class RecorderRobustness(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='gamelog-sim2.')
        cls.addClassCleanup(shutil.rmtree, cls.tmp, True)
        S = cls.S = {}
        play = lambda: [['sleep', 1.5], ['rmproc', 4242]]
        # R1: helper first, game 0.3 s later, both end together
        S['helper'] = Sim2(cls.tmp, 'helper', [['xproc', 4100, HELPER], ['sleep', 0.3], ['xproc', 4242, GAME_PROC],
                                               ['sleep', 1.5], ['rmproc', 4242], ['rmproc', 4100]])
        # R2a: launcher present, game after 1.2 s, START_WAIT 0.3
        S['patient_lutris'] = Sim2(cls.tmp, 'pl', [['xproc', 900, LAUNCHER_LUTRIS], ['sleep', 1.2], ['xproc', 4242, GAME_PROC],
                                                   ['sleep', 1.5], ['rmproc', 4242], ['rmproc', 900]], GAMELOG_START_WAIT='0.3')
        S['patient_umu'] = Sim2(cls.tmp, 'pu', [['xproc', 900, LAUNCHER_UMU], ['sleep', 1.2], ['xproc', 4242, GAME_PROC],
                                                ['sleep', 1.5], ['rmproc', 4242], ['rmproc', 900]], GAMELOG_START_WAIT='0.3')
        # R2b: same timing, no launcher
        S['impatient'] = Sim2(cls.tmp, 'imp', [['sleep', 1.2], ['xproc', 4242, GAME_PROC]] + play(), GAMELOG_START_WAIT='0.3')
        # R2c: a launcher that never produces a game
        S['forever'] = Sim2(cls.tmp, 'forever', [], timeout=8, GAMELOG_LAUNCH='/bin/true',
                            GAMELOG_START_WAIT='0.2', GAMELOG_START_WAIT_MAX='0.8')
        write_proc(S['forever'].root, 777, 'lutris-wrapper', ['lutris-wrapper: Path of Exile 2'])
        # R3: the session directory cannot be created
        S['fail'] = Sim2(cls.tmp, 'fail', [['mark', 'launched'], ['xproc', 4242, GAME_PROC], ['sleep', 1.0],
                                           ['rmproc', 4242], ['mark', 'removed']])
        shutil.rmtree(S['fail'].root / 'state')
        (S['fail'].root / 'state').mkdir()
        (S['fail'].root / 'state' / 'sessions').write_text('i am a file\n')
        # R4: config filtering
        for key, text, bom in (('ini', CONFIG_INI, False), ('ini_bom', CONFIG_INI, True), ('ini_flat', FLAT_INI, False)):
            S[key] = Sim2(cls.tmp, key, [['xproc', 4242, GAME_PROC]] + play())
            data = text.encode()
            (S[key].root / 'game' / 'production_Config.ini').write_bytes((b'\xef\xbb\xbf' if bom else b'') + data)
        # R5: proton version from the loaded files
        pdir = Path(cls.tmp) / 'proton' / 'x' / 'compat' / 'GE-Proton10-34'
        pdir.mkdir(parents=True)
        (pdir / 'version').write_text('1774856027 GE-Proton10-34\n')
        maps = ('7f0000000000-7f0000001000 r--p 00000000 08:01 11 /usr/lib/libc.so.6\n'
                f'7f0000002000-7f0000003000 r-xp 00000000 08:01 12 {pdir}/files/lib/wine/x86_64-unix/ntdll.so\n'
                f'7f0000004000-7f0000005000 r-xp 00000000 08:01 13 {pdir}/files/lib/wine/x86_64-unix/win32u.so\n')
        S['proton'] = Sim2(cls.tmp, 'proton', [['xproc', 4242, {'env': {**GAME_ENV, 'PROTONPATH': 'GE-Proton'},
                                                               'maps': maps, 'rss': 100000}]] + play())
        for s in S.values():
            cls.addClassCleanup(s.kill_stubs)
        for s in S.values():
            s.start()
        for s in S.values():
            s.finish()

    # ---- R1
    def test_helper_first_then_game_is_one_session_following_the_game_pid(self):
        s = self.S['helper']
        self.assertEqual(s.rc, 0, s.err)
        self.assertEqual(len(s.sessions()), 1)
        rows = [r.split(',') for r in (s.session() / 'sampler.csv').read_text().splitlines()[1:]]
        pids = [r[1] for r in rows]
        self.assertGreaterEqual(len(pids), 5, pids)
        self.assertEqual(set(pids[-3:]), {'4242'}, pids)
        self.assertLessEqual(set(pids), {'4100', '4242'})
        self.assertEqual(s.meta()['process']['comm'], 'PathOfExile.exe')

    # ---- R2
    def test_launcher_still_working_keeps_the_start_wait_going(self):
        for key in ('patient_lutris', 'patient_umu'):
            s = self.S[key]
            with self.subTest(key):
                self.assertEqual(s.rc, 0, s.err)
                self.assertNotEqual(s.meta()['status'], 'no-game')
                pids = {r.split(',')[1] for r in (s.session() / 'sampler.csv').read_text().splitlines()[1:]}
                self.assertIn('4242', pids)

    def test_without_launcher_it_gives_up_at_start_wait(self):
        s = self.S['impatient']
        self.assertEqual(s.rc, 1, s.err)
        self.assertEqual(s.meta()['status'], 'no-game')
        self.assertLess(s.elapsed, 1.1)  # the game only appears at 1.2 s
        self.assertGreaterEqual(s.elapsed, 0.25)

    def test_endless_launcher_is_bounded_by_start_wait_max(self):
        s = self.S['forever']
        self.assertEqual(s.rc, 1, f'{s.rc} {s.err}')
        self.assertEqual(s.meta()['status'], 'no-game')
        self.assertGreaterEqual(s.elapsed, 0.7)  # not at START_WAIT (0.2 s)
        self.assertLess(s.elapsed, 5)

    # ---- R3
    def test_recording_failure_does_not_end_the_process_before_the_game_ends(self):
        s = self.S['fail']
        self.assertIsNotNone(s.mark('launched'), 'the launch stub never ran')
        removed = s.mark('removed')
        self.assertIsNotNone(removed, 'the game never ended')
        self.assertEqual(s.rc, 1, s.err)
        self.assertGreaterEqual(s.t_end, removed - 0.05, 'gamelog exited while the game was still running')
        failed = [n for n in s.prio4() if any('Recording failed' in a for a in n)]
        self.assertEqual(len(failed), 1, s.notes())

    # ---- R4
    def kept(self, key):
        return (self.S[key].session() / 'config.ini').read_text()

    def test_config_keeps_only_the_four_sections(self):
        for key in ('ini', 'ini_bom'):
            text = self.kept(key)
            with self.subTest(key):
                for line in ('renderer_type=Vulkan', 'vsync=Off', 'networking_type=predictive',
                             'engine_multithreading_mode=enabled', 'master_volume=50'):
                    self.assertIn(line, text)
                for gone in ('gateway_id', 'xyzMARK', 'harmlessrealm', '[LOGIN]', '[UI]', 'ui_scale', 'key_inventory',
                             'ACTION_KEYS', 'last_zone', 'MARKZONE', 'CACHED_DATA'):
                    self.assertNotIn(gone, text)

    def test_config_drops_secret_keys_inside_kept_sections(self):
        for key in ('ini', 'ini_bom'):
            text = self.kept(key)
            with self.subTest(key):
                self.assertNotIn('MARKDISPTOKEN', text)
                self.assertNotIn('MARKGENPASS', text)

    def test_config_with_byte_order_mark_equals_one_without(self):
        self.assertEqual(self.kept('ini_bom'), self.kept('ini'))

    def test_config_without_sections_keeps_plain_lines_only(self):
        text = self.kept('ini_flat')
        for line in ('renderer_type=Vulkan', 'vsync=Off', 'some_plain_key=3'):
            self.assertIn(line, text)
        self.assertNotIn('MARKFLATPASS', text)

    # ---- R5
    def test_proton_version_comes_from_the_loaded_files_not_the_bare_name(self):
        s = self.S['proton']
        self.assertEqual(s.rc, 0, s.err)
        self.assertEqual(s.meta()['process']['proton_version'], 'GE-Proton10-34')


class Cli(CapCase):
    def run_cli(self, *args, **extra):
        return subprocess.run([GAMELOG, *args], env=base_env(self.root, **extra), cwd=self.root,
                              capture_output=True, text=True, timeout=30)

    def test_help_and_unknown_command(self):
        r = self.run_cli('--help')
        self.assertEqual(r.returncode, 0)
        self.assertIn('gamelog record', r.stdout)  # usage text lists the commands
        self.assertEqual(self.run_cli('frobnicate').returncode, 2)

    def mk_session(self, name, status, **files):
        d = self.root / 'state' / 'sessions' / name
        d.mkdir(parents=True)
        (d / 'meta.json').write_text(json.dumps({'status': status, 'start': 1700000000, 'end': 1700003600, 'game_start': 1700000010}))
        return d

    def test_list_one_line_per_session_with_status(self):
        self.mk_session('20240101-120000', 'ok')
        self.mk_session('20240102-130000', 'no-frames')
        r = self.run_cli('list')
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = [l for l in r.stdout.splitlines() if l.strip()]
        self.assertEqual(len(lines), 2, r.stdout)
        a = [l for l in lines if '20240101-120000' in l]
        b = [l for l in lines if '20240102-130000' in l]
        self.assertEqual(len(a), 1)
        self.assertEqual(len(b), 1)
        self.assertIn('ok', a[0])
        self.assertIn('no-frames', b[0])

    # ---- install-env
    def lutris(self, text, name='path-of-exile-2.yml'):
        d = self.root / 'lutris'
        d.mkdir(exist_ok=True)
        (d / name).write_text(text)
        return d / name

    @staticmethod
    def sys_env(text):
        lines = text.splitlines()
        i = lines.index('system:')
        out = {}
        for l in lines[i + 1:]:
            if l and not l.startswith(' '):
                break
            if l.startswith('    ') and ':' in l:
                k, v = l.strip().split(':', 1)
                out[k] = v.strip().strip("'")
        return out

    def test_install_env_sets_vars_and_writes_conf(self):
        y = self.lutris(YML)
        r = self.run_cli('install-env', GAMELOG_STATE='st')  # relative state dir on purpose
        self.assertEqual(r.returncode, 0, r.stderr)
        text = y.read_text()
        env = self.sys_env(text)
        conf = self.root / 'mango' / 'MangoHud.conf'
        self.assertEqual(env['MANGOHUD'], '1')
        self.assertEqual(env['MANGOHUD_CONFIGFILE'], str(conf))
        self.assertIn('    AFMF_ENABLE: 1', text.splitlines())
        game_before = YML.splitlines()[:YML.splitlines().index('system:')]
        self.assertEqual(text.splitlines()[:len(game_before)], game_before)
        self.assertEqual(text.count('MANGOHUD_CONFIGFILE'), 1)
        lines = conf.read_text().splitlines()
        self.assertIn('autostart_log=1', lines)
        self.assertIn('log_interval=0', lines)
        self.assertIn(f'output_folder={self.root}/st/incoming', lines)
        self.assertNotIn('no_display', conf.read_text())

    def test_install_env_twice_equals_once(self):
        y = self.lutris(YML)
        self.assertEqual(self.run_cli('install-env').returncode, 0)
        once = y.read_text()
        conf_once = (self.root / 'mango' / 'MangoHud.conf').read_text()
        self.assertEqual(self.run_cli('install-env').returncode, 0)
        self.assertEqual(y.read_text(), once)
        self.assertEqual((self.root / 'mango' / 'MangoHud.conf').read_text(), conf_once)

    def test_install_env_overwrites_old_values_in_system_block_only(self):
        text = "game:\n  env:\n    MANGOHUD: 'game'\nsystem:\n  env:\n    MANGOHUD: '0'\n    MANGOHUD_CONFIGFILE: '/old'\nrunner: w\n"
        y = self.lutris(text)
        self.assertEqual(self.run_cli('install-env').returncode, 0)
        out = y.read_text().splitlines()
        self.assertIn("    MANGOHUD: 'game'", out[:out.index('system:')])
        self.assertEqual(self.sys_env(y.read_text())['MANGOHUD'], '1')
        self.assertEqual(out[-1], 'runner: w')

    def test_install_env_without_yml_fails_and_writes_nothing(self):
        (self.root / 'lutris').mkdir()
        (self.root / 'lutris' / 'other-game.yml').write_text('name: x\n')
        r = self.run_cli('install-env')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(sorted(p.name for p in (self.root / 'lutris').iterdir()), ['other-game.yml'])
        self.assertEqual((self.root / 'lutris' / 'other-game.yml').read_text(), 'name: x\n')

    # ---- prune
    def age_session(self, days, frames=b'F' * 400):
        name = (datetime.now() - timedelta(days=days)).strftime('%Y%m%d-%H%M%S')
        d = self.root / 'state' / 'sessions' / name
        (d / 'frames').mkdir(parents=True)
        (d / 'frames' / 'a.csv.gz').write_bytes(frames)
        for f in ('meta.json', 'summary.json', 'events.jsonl', 'sampler.csv', 'config.ini'):
            (d / f).write_text('{}\n')
        return d

    def test_prune_by_age(self):
        d1, d29, d31, d179, d181 = (self.age_session(x) for x in (1, 29, 31, 179, 181))
        r = self.run_cli('prune')
        self.assertEqual(r.returncode, 0, r.stderr)
        full = ['config.ini', 'events.jsonl', 'frames', 'meta.json', 'sampler.csv', 'summary.json']
        nof = [f for f in full if f != 'frames']
        ls = lambda d: sorted(p.name for p in d.iterdir()) if d.exists() else None
        self.assertEqual(ls(d1), full)
        self.assertEqual(ls(d29), full)  # 29 days keeps frames
        self.assertEqual(ls(d31), nof)
        self.assertEqual(ls(d179), nof)
        self.assertEqual(ls(d181), ['meta.json', 'summary.json'])

    def test_prune_by_age_leaves_a_folder_without_a_date_name_alone(self):
        d = self.root / 'state' / 'sessions' / 'reference-baseline'
        (d / 'frames').mkdir(parents=True)
        (d / 'frames' / 'a.csv.gz').write_bytes(b'F' * 400)
        for f in ('meta.json', 'summary.json', 'events.jsonl'):
            (d / f).write_text('{}\n')
        old = time.time() - 400 * 86400
        for p in [d, *d.rglob('*')]:
            os.utime(p, (old, old))
        r = self.run_cli('prune')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(p.name for p in d.iterdir()), ['events.jsonl', 'frames', 'meta.json', 'summary.json'])

    def test_prune_cap_deletes_oldest_frames_first(self):
        newest, mid, oldest = (self.age_session(x) for x in (1, 2, 3))
        self.cap("c.prune(cap_bytes=900); out = 0")
        self.assertFalse((oldest / 'frames').exists())
        self.assertTrue((mid / 'frames').exists())
        self.assertTrue((newest / 'frames').exists())
        self.assertTrue((oldest / 'meta.json').exists())  # only frames go for the cap

    def test_prune_cap_never_deletes_newest_frames(self):
        newest, mid, oldest = (self.age_session(x) for x in (1, 2, 3))
        self.cap("c.prune(cap_bytes=10); out = 0")
        self.assertFalse((oldest / 'frames').exists())
        self.assertFalse((mid / 'frames').exists())
        self.assertTrue((newest / 'frames' / 'a.csv.gz').exists())

    def test_prune_under_cap_deletes_nothing(self):
        ds = [self.age_session(x) for x in (1, 2, 3)]
        self.cap("c.prune(); out = 0")
        self.assertTrue(all((d / 'frames').exists() for d in ds))


if __name__ == '__main__':
    unittest.main()
