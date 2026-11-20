"""Spec-derived tests for gamelog_lib.analyze (written without reading the implementation).

Every expected number below is computed by hand from the fixture layout, never by calling the code under test.
Set GAMELOG_TOOL_DIR to run against a copy of the tool directory.
"""
import copy
import csv
import gzip
import html as htmllib
import json
import math
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
TOOL_DIR = os.environ.get('GAMELOG_TOOL_DIR') or str(Path(__file__).resolve().parents[1])
sys.path.insert(0, TOOL_DIR)
from gamelog_lib import analyze  # noqa: E402

S = 1_700_000_000
U0 = 5_000_000

BASE_META = {
    'start': S, 'game_start': S + 1, 'end': S + 100, 'status': 'ok', 'exit': 'graceful',
    'recorder_cpu_s': 0.02, 'crit_counts': {},
    'settings': {
        'kernel': '6.12.1-arch1', 'nvidia_driver': '570.86', 'game_mode_on': True, 'proton_pinned': True,
        'lutris_env': {'DXVK_ASYNC': '1', 'MANGOHUD': '1', 'MANGOHUD_CONFIGFILE': '/home/u/mh.conf'},
        'lutris_ignored_env': [], 'swap_total_mb': 8192, 'swap_free_mb': 8000,
        'vram_total_mib': 10000, 'vram_used_mib_at_launch': 500,
        'packages': {'mesa': '25.0', 'wine': '9.0'}, 'governor': 'performance', 'epp': 'performance',
    },
    'process': {'proton_version': 'GE-Proton11-12', 'sync': 'fsync', 'afmf_loaded': False,
                'mangohud_loaded': True, 'env': {}},
}
DEFAULT_INI = {
    'framerate_limit': '60', 'framerate_limit_enabled': 'true', 'renderer_type': 'Vulkan', 'vsync': 'Off',
    'upscale': 'NIS', 'upscale_resolution': 'UltraPerformance', 'texture_quality': 'TextureQualityLow',
    'engine_multithreading_mode': 'enabled', 'key_inventory': 'i', 'sound_volume': '50',
}
SAMPLER_COLS = ['t', 'gpu_util', 'vram_used', 'vram_total', 'proc_vram', 'cpu_temp', 'gpu_temp', 'gpu_w', 'cpu_w',
                'rss_mb', 'top_threads', 'rtt_ms', 'psi_io_ms', 'psi_mem_ms', 'psi_cpu_ms', 'thr_hw',
                'thr_hw_thermal', 'thr_sw_power', 'thr_sw_thermal', 'cache_mb', 'cpu_total']
DEFAULT_ROW = {'gpu_util': 50, 'vram_used': 4000, 'vram_total': 10000, 'proc_vram': 3000, 'cpu_temp': 60,
               'gpu_temp': 65, 'gpu_w': 100, 'cpu_w': 50, 'rss_mb': 2000, 'top_threads': 'Main:40|Render:30',
               'rtt_ms': 20, 'psi_io_ms': 0, 'psi_mem_ms': 0, 'psi_cpu_ms': 0, 'thr_hw': 0, 'thr_hw_thermal': 0,
               'thr_sw_power': 0, 'thr_sw_thermal': 0, 'cache_mb': 100, 'cpu_total': 30}
FRAME_HEADER = ('fps,frametime,cpu_load,cpu_power,gpu_load,cpu_temp,gpu_temp,gpu_core_clock,gpu_mem_clock,'
                'gpu_vram_used,gpu_power,ram_used,swap_used,process_rss,cpu_mhz,elapsed')


def merge(base, over):
    out = copy.deepcopy(base)
    for key, value in (over or {}).items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out


def ev(off, kind, **extra):
    """An event at true time S+off: t is floored, uptime_ms keeps the sub-second part."""
    return (off, {'t': math.floor(S + off), 'uptime_ms': U0 + round(off * 1000), 'kind': kind, **extra})


def runs_to_frames(runs):
    """runs: ('at', start_s) or (ms, count). Returns [(end_offset_s, ms)]."""
    out, cur = [], 0.0
    for run in runs:
        if run[0] == 'at':
            cur = run[1]
            continue
        ms, n = run
        for i in range(n):
            out.append((cur + (i + 1) * ms / 1000.0, ms))
        cur += n * ms / 1000.0
    return out


def write_frames(path, frames, l0, style=0, truncated=False):
    lines = []
    if style == 0:
        lines += ['v1', '---------------------SYSTEM INFO---------------------',
                  'os,cpu,gpu,ram,kernel,driver,cpuscheduler',
                  'Arch Linux,AMD Ryzen 7, 5800X,NVIDIA GeForce RTX,32768,6.12.1,570.86,performance',
                  '--------------------FRAME METRICS--------------------']
    elif style == 1:
        lines += ['v0.8.4']
    lines.append(FRAME_HEADER)
    last_elapsed = None
    for end_off, ms in frames:
        elapsed = round((end_off - l0) * 1e9)
        last_elapsed = elapsed
        lines.append(f'{1000.0 / ms:.1f},{ms},10,50,60,50,60,2000,9000,4000,100,8,0,2000,4500,{elapsed}')
    text = '\n'.join(lines) + '\n'
    if truncated:
        text += '99.0,10.0,10,50'
    with gzip.open(path, 'wt') as fh:
        fh.write(text)
    mtime = S + frames[-1][0]
    os.utime(path, (mtime, mtime))


def build(root, name, *, events=(), files=(), sampler=None, meta=None, ini=None, kernel=None, end=100.0):
    d = Path(root) / name
    d.mkdir(parents=True)
    m = merge(BASE_META, meta)
    m['end'] = S + int(end)
    (d / 'meta.json').write_text(json.dumps(m))
    merged_ini = {**DEFAULT_INI, **(ini or {})}
    (d / 'config.ini').write_text(''.join(f'{k}={v}\n' for k, v in merged_ini.items() if v is not None))
    (d / 'events.jsonl').write_text(''.join(json.dumps(e) + '\n' for _, e in sorted(events, key=lambda p: p[0])))
    if files:
        (d / 'frames').mkdir()
        for fname, frames, l0, style, truncated in files:
            write_frames(d / 'frames' / fname, frames, l0, style, truncated)
    if sampler is not None:
        with open(d / 'sampler.csv', 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=SAMPLER_COLS, restval='')
            w.writeheader()
            w.writerows(sampler)
    if kernel is not None:
        (d / 'kernel.log').write_text(kernel)
    return d


def clock_anchors():
    """Events whose sub-second parts sit at both ends of a second, so uptime_ms pins the clock to a few ms."""
    return [ev(1.002, 'renderer', value='Vulkan'), ev(2.996, 'renderer', value='Vulkan')]


def micro(root, name, runs, *, events=(), meta=None, ini=None, kernel=None, load_name='Loading Micro', area='MapMicro'):
    """One zone, loading ends at 7.43, play frames from 9.0."""
    frames = runs_to_frames([('at', 9.0)] + list(runs))
    end = frames[-1][0] + 1.0
    evs = [ev(0.0, 'start'), ev(5.31, 'zone', level=3, area=area), ev(7.43, 'loading', name=load_name, seconds=1.0)]
    evs += clock_anchors() + list(events)
    return build(root, name, events=evs, files=[('m.csv.gz', frames, 1.0, 0, False)], meta=meta, ini=ini,
                 kernel=kernel, end=end)


def second_runs(k, kind):
    runs = [('at', k + 0.01)]
    table = {'n': [(10, 98)], 'slow': [(20, 49)], 'f58': [(1000 / 58, 56)], 'f56': [(1000 / 56, 55)],
             'f75': [(1000 / 75, 73)], 'f85': [(1000 / 85, 83)], 'stut': [(10, 46), (40, 1), (10, 47)], 'short': [(10, 30)]}
    return runs + table[kind]


def sec_session(root, name, *, first, last, kinds=None, over=None, missing=(), sampler=True, load_off=12.41,
                load_s=2.0, zone_off=8.03, extra_events=(), meta=None, ini=None, kernel=None, gpu=None,
                load_name='Cause Test', area='Map_Test', end=None):
    kinds = kinds or {}
    runs = []
    for k in range(first, last + 1):
        runs += second_runs(k, kinds.get(k, 'n'))
    frames = runs_to_frames(runs)
    end = end or last + 1.0
    evs = [ev(0.0, 'start'), ev(zone_off, 'zone', level=70, area=area),
           ev(load_off, 'loading', name=load_name, seconds=load_s)]
    evs += [ev(o, 'renderer', value='Vulkan') for o in (20.77, 33.52, 47.88, 61.14, 74.65) if o < end]
    evs += clock_anchors() + list(extra_events)
    rows = None
    if sampler:
        rows = []
        for k in range(0, int(end)):
            if k in missing:
                continue
            row = {**DEFAULT_ROW, 't': S + k}
            if gpu is not None:
                row['gpu_util'] = gpu
            row.update((over or {}).get(k, {}))
            rows.append(row)
    return build(root, name, events=evs, files=[('s.csv.gz', frames, 5.0, 0, False)], sampler=rows, meta=meta,
                 ini=ini, kernel=kernel, end=end)


def build_main(root, name, load1='Loading One'):
    evs = [ev(0.0, 'start'), ev(1.23, 'renderer', value='Vulkan'), ev(3.77, 'present_mode', value='Mailbox'),
           ev(10.30, 'zone', level=1, area='Hideout_Test'), ev(14.37, 'loading', name=load1, seconds=3.0),
           ev(30.58, 'reflex', value='On'), ev(44.91, 'renderer', value='Vulkan'),
           ev(56.04, 'zone', level=68, area='MapSwamp'), ev(59.11, 'loading', name='Loading Two', seconds=2.0),
           ev(75.46, 'renderer', value='Vulkan'), ev(90.33, 'focus', value='Lost'), ev(95.41, 'focus', value='Gained'),
           ev(110.72, 'present_mode', value='Mailbox')] + clock_anchors()
    file1 = runs_to_frames([
        ('at', 0.1), (16, 600),                      # menu
        ('at', 11.0), (100, 30),                     # loading screen 1 (excluded)
        ('at', 14.62), (7, 1),                       # 0.25 s after loading ended: still excluded
        ('at', 15.0), (10, 1000), (24, 1), (10, 1000), (30, 1), (10, 1000), (80, 3), (10, 1000),
        ('at', 55.8), (12, 1),                       # just before the next zone event: still area 1
        ('at', 56.64), (120, 20),                    # loading screen 2 (excluded)
        ('at', 59.36), (8, 1),                       # 0.25 s after loading ended: excluded
    ])
    file2 = runs_to_frames([
        ('at', 60.0), (20, 1500),
        ('at', 90.6), (50, 90),                      # paused while unfocused
        ('at', 95.66), (8, 1),                       # 0.25 s after focus gained: excluded
        ('at', 96.1), (20, 1500),
    ])
    return build(root, name, events=evs, files=[('game-1.csv.gz', file1, 0.1, 0, False),
                                                 ('game-2.csv.gz', file2, 59.8, 1, True)], end=127.0)


def levels(summary):
    return [f['level'] for f in summary['findings']]


def texts(summary, level):
    return [f['text'] for f in summary['findings'] if f['level'] == level]


class Tmp(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name


class SharedTmp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls._tmp.cleanup)
        cls.root = cls._tmp.name


class ToolUnderTest(unittest.TestCase):
    def test_imported_from_the_requested_directory(self):
        self.assertTrue(Path(analyze.__file__).resolve().is_relative_to(Path(TOOL_DIR).resolve()), analyze.__file__)


class MainSession(SharedTmp):
    """Two areas, two loading screens, a pause, menu frames, two frame files, a truncated last row."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.path = build_main(cls.root, 'main-session')
        cls.summary, cls.detail = analyze.analyze(str(cls.path))

    def test_overall_counts_only_play_frames(self):
        o = self.summary['overall']
        # area 1: 4000x10 + 12 + 24 + 30 + 3x80 ms = 4006 frames; area 2: 3000x20 ms. Menu, loading, probes, pause excluded.
        self.assertEqual(o['frames'], 7006)
        self.assertAlmostEqual(o['seconds'], 100.3, delta=0.11)
        self.assertAlmostEqual(o['avg_fps'], 69.85, delta=0.1)
        self.assertAlmostEqual(o['median_fps'], 100.0, delta=0.01)
        self.assertEqual((o['p95_ms'], o['p99_ms'], o['p999_ms'], o['max_ms']), (20, 20, 20, 80))
        self.assertAlmostEqual(o['low1_fps'], 50.0, delta=0.01)
        self.assertAlmostEqual(o['low01_fps'], 50.0, delta=0.01)

    def test_zone_list_names_levels_kinds_and_load_times(self):
        z = self.summary['zones']
        self.assertEqual([x['area'] for x in z], ['Hideout_Test', 'MapSwamp'])
        self.assertEqual([x['name'] for x in z], ['Loading One', 'Loading Two'])
        self.assertEqual([x['level'] for x in z], [1, 68])
        self.assertEqual([x['kind'] for x in z], ['hideout', 'map'])
        self.assertEqual([x['load_s'] for x in z], [3.0, 2.0])
        for x in z:
            self.assertLess(x['start'], x['end'])

    def test_each_zone_gets_only_its_own_frames(self):
        a, b = (x['stats'] for x in self.summary['zones'])
        self.assertEqual(a['frames'], 4006)
        self.assertAlmostEqual(a['seconds'], 40.3, delta=0.11)
        self.assertAlmostEqual(a['avg_fps'], 99.4, delta=0.1)
        self.assertEqual((a['p95_ms'], a['p99_ms'], a['max_ms']), (10, 10, 80))
        # index int(0.999*4006)=4001 of the sorted list: 4000x10, 12, 24, 30, 80x3 -> 24
        self.assertEqual(a['p999_ms'], 24)
        self.assertAlmostEqual(a['low01_fps'], 1000 / 24, delta=0.06)
        self.assertAlmostEqual(a['low1_fps'], 100.0, delta=0.01)
        self.assertEqual(b['frames'], 3000)
        self.assertAlmostEqual(b['seconds'], 60.0, delta=0.05)
        self.assertAlmostEqual(b['avg_fps'], 50.0, delta=0.1)
        self.assertEqual((b['p95_ms'], b['p99_ms'], b['p999_ms'], b['max_ms']), (20, 20, 20, 20))

    def test_stutters_are_counted_per_zone_and_overall(self):
        z = self.summary['zones']
        self.assertEqual((z[0]['stutters'], z[1]['stutters']), (2, 0))  # one 30 ms frame, one cluster of three 80 ms
        s = self.summary
        self.assertEqual(s['stutters'], 2)
        self.assertEqual(s['worst_stutter_ms'], 80)
        self.assertAlmostEqual(s['stutters_per_10min'], 2 / (100.306 / 60) * 10, delta=0.15)

    def test_kinds_aggregate_their_areas(self):
        k = self.summary['kinds']
        self.assertEqual(set(k), {'hideout', 'map'})
        self.assertEqual(k['hideout']['frames'], 4006)
        self.assertEqual(k['map']['frames'], 3000)
        self.assertAlmostEqual(k['hideout']['stutters_per_10min'], 2 / 40.306 * 600, delta=0.15)
        self.assertEqual(k['map']['stutters_per_10min'], 0)

    def test_metadata_keys(self):
        s = self.summary
        self.assertEqual(s['session'], 'main-session')
        self.assertEqual((s['status'], s['exit']), ('ok', 'graceful'))
        self.assertEqual(s['fps_cap'], 60)
        self.assertEqual(s['frame_basis'], 'real')

    def test_game_log_events_are_summarised(self):
        g = self.summary['game_log']
        self.assertEqual(g['present_mode'], 'Mailbox')
        self.assertEqual(g['renderer'], 'Vulkan')
        self.assertEqual(g['reflex'], 'On')

    def test_write_summary_writes_the_same_data(self):
        again, _ = analyze.write_summary(str(self.path))
        on_disk = json.loads((self.path / 'summary.json').read_text())
        self.assertEqual(on_disk, json.loads(json.dumps(again)))
        self.assertEqual(on_disk['overall']['frames'], 7006)


class Percentiles(Tmp):
    def test_ten_slow_frames_in_a_thousand_put_p99_on_the_slow_ones(self):
        path = micro(self.root, 'p10', [(10, 99), (40, 1)] * 10)
        o = analyze.analyze(str(path))[0]['overall']
        self.assertEqual(o['frames'], 1000)
        self.assertEqual((o['p95_ms'], o['p99_ms'], o['p999_ms'], o['max_ms']), (10, 40, 40, 40))
        self.assertAlmostEqual(o['low1_fps'], 25.0, delta=0.01)
        self.assertAlmostEqual(o['low01_fps'], 25.0, delta=0.01)
        self.assertAlmostEqual(o['median_fps'], 100.0, delta=0.01)
        self.assertAlmostEqual(o['avg_fps'], 1000 / 10.3, delta=0.6)

    def test_nine_slow_frames_in_a_thousand_leave_p99_at_the_normal_length(self):
        runs = [(10, 110), (40, 1)] * 9 + [(10, 1)]
        path = micro(self.root, 'p9', runs)
        s = analyze.analyze(str(path))[0]
        o = s['overall']
        self.assertEqual(o['frames'], 1000)
        self.assertEqual((o['p99_ms'], o['p999_ms']), (10, 40))
        self.assertAlmostEqual(o['low1_fps'], 100.0, delta=0.01)
        self.assertAlmostEqual(o['low01_fps'], 25.0, delta=0.01)
        self.assertEqual(s['stutters'], 9)


class StutterRules(Tmp):
    def stutters(self, runs, name):
        s = analyze.analyze(str(micro(self.root, name, runs)))[0]
        return s['stutters'], s['worst_stutter_ms']

    def test_one_30ms_frame_among_10ms_frames_is_one_stutter(self):
        self.assertEqual(self.stutters([(10, 500), (30, 1), (10, 500)], 'a'), (1, 30))

    def test_24ms_frame_is_under_the_absolute_limit(self):
        # 24 ms is 4.8x the 5 ms median, so only the 25 ms floor keeps it from counting
        self.assertEqual(self.stutters([(5, 500), (24, 1), (5, 500)], 'b')[0], 0)
        self.assertEqual(self.stutters([(10, 500), (24, 1), (10, 500)], 'b2')[0], 0)

    def test_25ms_frame_over_5ms_frames_counts(self):
        self.assertEqual(self.stutters([(5, 500), (25, 1), (5, 500)], 'b3'), (1, 25))

    def test_25ms_frame_is_exactly_on_both_limits(self):
        self.assertEqual(self.stutters([(10, 500), (25, 1), (10, 500)], 'c'), (1, 25))

    def test_40ms_over_16_7ms_is_under_the_relative_limit(self):
        self.assertEqual(self.stutters([(16.7, 500), (40, 1), (16.7, 500)], 'd')[0], 0)

    def test_a_steady_33ms_section_has_no_stutters(self):
        self.assertEqual(self.stutters([(33, 600)], 'e')[0], 0)

    def test_three_80ms_frames_in_a_row_are_one_stutter(self):
        self.assertEqual(self.stutters([(10, 300), (80, 3), (10, 300)], 'f'), (1, 80))

    def test_stutter_frames_80ms_apart_merge_and_the_longest_gives_the_length(self):
        self.assertEqual(self.stutters([(10, 300), (40, 1), (10, 3), (50, 1), (10, 300)], 'g'), (1, 50))

    def test_stutter_frames_330ms_apart_stay_separate(self):
        self.assertEqual(self.stutters([(10, 300), (40, 1), (10, 29), (40, 1), (10, 300)], 'h')[0], 2)


class PlayTimeRules(Tmp):
    def test_unfocused_time_that_is_never_regained_runs_to_the_end(self):
        runs = [(10, 500), ('at', 14.5), (20, 100)]  # lost at 14.3, never gained
        path = micro(self.root, 'lost', runs, events=[ev(14.3, 'focus', value='Lost')])
        o = analyze.analyze(str(path))[0]['overall']
        self.assertEqual(o['frames'], 500)
        self.assertEqual(o['max_ms'], 10)

    def test_frames_before_the_first_loading_screen_ended_are_not_play_time(self):
        frames = runs_to_frames([('at', 0.5), (16, 300)])
        path = build(self.root, 'menu', events=[ev(0.0, 'start')], files=[('a.csv.gz', frames, 0.5, 0, False)], end=10)
        s = analyze.analyze(str(path))[0]
        self.assertIsNone(s['overall'])
        self.assertIn('bad', levels(s))

    def test_session_without_frames_dir_does_not_raise(self):
        path = build(self.root, 'noframes', events=[ev(0.0, 'start')], end=10)
        s = analyze.analyze(str(path))[0]
        self.assertIsNone(s['overall'])
        self.assertIn('bad', levels(s))
        self.assertEqual(s['zones'], [])
        analyze.write_summary(str(path))
        self.assertTrue((path / 'summary.json').exists())

    def test_zone_kinds_zone_attribution_and_per_kind_stutter_rates(self):
        spec = [  # (area id, runs of play frames)
            ('HideoutTest', [(8, 1250)]),
            ('G1_Town', [(10, 1000)]),
            ('G2_TOWN', [(12.5, 800)]),
            ('MapForest', [(16, 300), (60, 1), (16, 324)]),
            ('Sewers_Map', [(20, 249), (80, 1), (20, 250)]),
            ('myhideout', [(25, 400)]),
            ('G9_Empty', []),
        ]
        evs, runs = [ev(0.0, 'start')] + clock_anchors(), []
        for i, (area, play) in enumerate(spec):
            z = 5.3 + 30 * i
            evs += [ev(z, 'zone', level=i + 1, area=area), ev(z + 3.1, 'loading', name=f'Load{i}', seconds=1.5)]
            if play:
                runs += [('at', z + 4.1)] + play
        frames = runs_to_frames(runs)
        path = build(self.root, 'kinds', events=evs, files=[('k.csv.gz', frames, 1.0, 0, False)], end=5.3 + 30 * 7 + 5)
        s = analyze.analyze(str(path))[0]
        z = s['zones']
        self.assertEqual([x['area'] for x in z], [a for a, p in spec if p])
        self.assertEqual([x['kind'] for x in z], ['hideout', 'town', 'town', 'map', 'other', 'other'])
        self.assertEqual([x['name'] for x in z], [f'Load{i}' for i in range(6)])
        self.assertEqual([x['stats']['frames'] for x in z], [1250, 1000, 800, 625, 500, 400])
        self.assertEqual([x['stats']['p99_ms'] for x in z], [8, 10, 12.5, 16, 20, 25])
        self.assertEqual([x['stutters'] for x in z], [0, 0, 0, 1, 1, 0])
        k = s['kinds']
        self.assertEqual(set(k), {'hideout', 'town', 'map', 'other'})
        self.assertEqual([k[n]['frames'] for n in ('hideout', 'town', 'map', 'other')], [1250, 1800, 625, 900])
        self.assertAlmostEqual(k['town']['avg_fps'], 90.0, delta=0.1)
        self.assertAlmostEqual(k['other']['avg_fps'], 900 / 20.06, delta=0.1)
        self.assertEqual(k['hideout']['stutters_per_10min'], 0)
        self.assertEqual(k['town']['stutters_per_10min'], 0)
        self.assertAlmostEqual(k['map']['stutters_per_10min'], 1 / 10.044 * 600, delta=0.5)
        self.assertAlmostEqual(k['other']['stutters_per_10min'], 1 / 20.06 * 600, delta=0.5)
        self.assertEqual(s['stutters'], 2)


class SlowSecondsAndCauses(SharedTmp):
    """One session with a slow second for every branch of the cause ladder (cap 60, so slow = under 57 fps)."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        kinds = {15: 'slow', 16: 'slow', 17: 'slow', 25: 'f58', 26: 'f56', 36: 'slow', 40: 'slow', 41: 'slow',
                 50: 'slow', 51: 'slow', 52: 'slow', 53: 'slow', 54: 'slow', 55: 'slow', 56: 'slow', 57: 'slow',
                 58: 'slow', 59: 'slow', 61: 'slow', 70: 'stut', 80: 'slow'}
        over = {k: {'gpu_util': 100, 'vram_used': 9900, 'cpu_temp': 99, 'gpu_temp': 90, 'rtt_ms': 900}
                for k in range(0, 10)}
        over.update({k: {'gpu_util': 100, 'vram_used': 9900, 'cpu_temp': 99, 'gpu_temp': 90} for k in (10, 11)})
        over.update({k: {'rtt_ms': 200} for k in range(20, 30)})
        over.update({
            16: {'gpu_util': 97},
            17: {'top_threads': 'Main:95|Render:30'},
            30: {'gpu_temp': 70},
            40: {'vram_used': 9500, 'thr_hw': 1, 'gpu_util': 99, 'psi_io_ms': 500},
            41: {'vram_used': 9200},
            50: {'thr_sw_thermal': 1, 'gpu_util': 99},
            51: {'cpu_temp': 93},
            52: {'cpu_temp': 92},
            53: {'psi_io_ms': 100},
            54: {'psi_io_ms': 99, 'psi_mem_ms': 99, 'psi_cpu_ms': 199},
            55: {'psi_cpu_ms': 200},
            56: {'psi_mem_ms': 100},
            57: {'gpu_util': 95, 'top_threads': 'Main:99|Render:1'},
            58: {'gpu_util': 94, 'top_threads': 'Main:90|Other:20'},
            59: {'gpu_util': 94, 'top_threads': 'Main:89|Other:95'},
            60: {'gpu_util': 99}, 62: {'gpu_util': 99},
            70: {'gpu_util': 99},
        })
        cls.path = sec_session(cls.root, 'causes', first=13, last=89, kinds=kinds, over=over, missing={61},
                               extra_events=[ev(80.5, 'vram_warning')])
        cls.summary, _ = analyze.analyze(str(cls.path))

    def test_slow_seconds_are_counted_against_95_percent_of_the_cap(self):
        # 15,16,17,26(56 fps),36,40,41,50-59,61,70(stutter),80 = 20; second 25 runs at 58 fps and is not slow
        self.assertEqual(self.summary['slow_seconds'], 20)
        self.assertAlmostEqual(self.summary['slow_share'], 20 / 77, delta=0.005)
        self.assertEqual(self.summary['fps_cap'], 60)

    def test_every_slow_second_gets_exactly_one_cause_in_priority_order(self):
        self.assertEqual(self.summary['causes'], {'new_area': 3, 'gpu': 4, 'vram': 2, 'throttle': 2,
                                                    'pressure': 3, 'cpu': 1, 'unexplained': 5})

    def test_only_one_stutter_second_exists(self):
        self.assertEqual(self.summary['stutters'], 1)

    def test_system_numbers_cover_play_seconds_only(self):
        sy = self.summary['system']
        self.assertEqual(sy['vram_peak_mib'], 9500)      # pre-play rows reach 9900
        self.assertEqual(sy['vram_total_mib'], 10000)
        self.assertEqual(sy['cpu_temp_max'], 93)          # pre-play rows reach 99
        self.assertEqual(sy['gpu_temp_max'], 70)          # pre-play rows reach 90
        self.assertEqual(sy['gpu_util_median'], 50)
        self.assertEqual(sy['rtt_median_ms'], 20)
        self.assertEqual(sy['rtt_p95_ms'], 200)           # pre-play 900 ms rows would lift it to 900
        self.assertIn('rtt_spikes', sy)
        self.assertIn('recorder_cpu_pct', sy)

    def test_a_slow_share_over_two_percent_earns_no_good_finding(self):
        self.assertNotIn('good', levels(self.summary))

    def test_vram_warning_event_is_a_bad_finding_about_graphics_memory(self):
        self.assertTrue(any('memory' in t.lower() for t in texts(self.summary, 'bad')))
        self.assertEqual(self.summary['game_log']['vram_warnings'], 1)


class SlowSecondsWithoutCapOrSampler(Tmp):
    def test_without_a_cap_slow_means_under_80_percent_of_median_fps(self):
        kinds = {30: 'f85', 45: 'f75'}
        path = sec_session(self.root, 'nocap', first=13, last=60, kinds=kinds, sampler=False,
                           ini={'framerate_limit_enabled': 'false'})
        s = analyze.analyze(str(path))[0]
        self.assertIsNone(s['fps_cap'])
        self.assertEqual(s['slow_seconds'], 1)     # 75 fps < 80; 85 fps is fine
        self.assertAlmostEqual(s['slow_share'], 1 / 48, delta=0.003)
        self.assertEqual(s['causes'], {'unexplained': 1})   # 33 s after loading: outside the 20 s window
        self.assertAlmostEqual(s['overall']['median_fps'], 100.0, delta=0.01)

    def test_a_limit_the_game_never_reaches_is_judged_like_no_limit(self):
        # 240 fps limit, game runs about 100: a second is slow only against the median, as without a limit.
        kinds = {30: 'f85', 45: 'f75'}
        path = sec_session(self.root, 'farcap', first=13, last=60, kinds=kinds, sampler=False,
                           ini={'framerate_limit_enabled': 'true', 'framerate_limit': '240'})
        s = analyze.analyze(str(path))[0]
        self.assertEqual(s['fps_cap'], 240)
        self.assertEqual(s['slow_seconds'], 1)
        self.assertFalse(any('limit' in x for x in texts(s, 'good')), s['findings'])

    def test_power_cap_at_full_load_is_the_card_at_its_limit_not_heat(self):
        # The card sits at its own power limit (270 W here) whenever it is fully busy; that is not overheating.
        path = sec_session(self.root, 'powercap', first=13, last=60, kinds={30: 'slow', 31: 'slow'},
                           over={30: {'thr_sw_power': 1, 'gpu_util': 99, 'gpu_temp': 65},
                                 31: {'thr_sw_power': 1, 'gpu_util': 99, 'gpu_temp': 65, 'thr_sw_thermal': 1}})
        s = analyze.analyze(str(path))[0]
        self.assertEqual(s['causes'], {'gpu': 1, 'throttle': 1})
        self.assertNotIn('power', analyze.CAUSES['throttle'])

    def test_seconds_with_less_than_half_a_second_of_play_are_not_counted(self):
        path = sec_session(self.root, 'short', first=13, last=22, kinds={18: 'f75', 20: 'short'}, sampler=False,
                           ini={'framerate_limit_enabled': 'false'})
        s = analyze.analyze(str(path))[0]
        self.assertEqual(s['slow_seconds'], 1)
        self.assertAlmostEqual(s['slow_share'], 1 / 9, delta=0.005)   # 9 counted seconds, not 10

    def test_fps_cap_reading(self):
        for ini, expect in [({'framerate_limit_enabled': 'TRUE', 'framerate_limit': '144'}, 144),
                            ({'framerate_limit_enabled': 'false', 'framerate_limit': '144'}, None),
                            ({'framerate_limit_enabled': 'False', 'framerate_limit': '60'}, None),
                            ({'framerate_limit_enabled': None, 'framerate_limit': '60'}, None)]:
            with self.subTest(ini=ini):
                path = micro(self.root, f'cap{len(os.listdir(self.root))}', [(10, 300)], ini=ini)
                self.assertEqual(analyze.analyze(str(path))[0]['fps_cap'], expect)


class FrameBasis(Tmp):
    def basis(self, ms, *, afmf, cap=True):
        ini = {} if cap else {'framerate_limit_enabled': 'false'}
        meta = {'process': {'afmf_loaded': afmf}}
        path = micro(self.root, f'fb{len(os.listdir(self.root))}', [(ms, int(10000 / ms))], ini=ini, meta=meta)
        return analyze.analyze(str(path))[0]['frame_basis']

    def test_real_without_frame_generation(self):
        self.assertEqual(self.basis(8, afmf=False), 'real')

    def test_unknown_with_frame_generation_and_no_cap(self):
        self.assertEqual(self.basis(10, afmf=True, cap=False), 'unknown')

    def test_doubled_at_1_8_times_the_cap_and_real_below(self):
        self.assertEqual(self.basis(9.2, afmf=True), 'doubled')   # 108.7 fps vs 60 cap
        self.assertEqual(self.basis(9.4, afmf=True), 'real')      # 106.4 fps
        self.assertEqual(self.basis(10, afmf=True), 'real')


class Findings(Tmp):
    def summary(self, name, **kw):
        return analyze.analyze(str(micro(self.root, name, kw.pop('runs', [(10, 500)]), **kw)))[0]

    def test_clean_capped_session_is_good_and_names_the_cap(self):
        s = self.summary('clean')
        self.assertNotIn('bad', levels(s))
        self.assertTrue(any('60' in t for t in texts(s, 'good')), s['findings'])

    def test_not_graceful_exit_is_bad(self):
        s = self.summary('crash', meta={'exit': 'not graceful'})
        self.assertIn('bad', levels(s))
        self.assertEqual(s['exit'], 'not graceful')

    def test_xid_line_is_bad_and_mentions_the_driver(self):
        log = 'Nov 18 10:00:01 archpc kernel: NVRM: Xid (PCI:0000:01:00): 79, pid=1234, GPU has fallen off the bus.\n'
        s = self.summary('xid', kernel=log)
        self.assertTrue(any('driver' in t.lower() for t in texts(s, 'bad')), s['findings'])
        self.assertEqual(len(s['kernel']['xid']), 1)
        self.assertIn('Xid', s['kernel']['xid'][0])

    def test_flip_timeout_alone_is_only_info(self):
        base = len(texts(self.summary('base'), 'info'))
        log = 'Nov 18 10:00:02 archpc kernel: nvidia-modeset: ERROR: GPU:0: Flip event timeout on head 0\n'
        s = self.summary('flip', kernel=log)
        self.assertEqual(s['kernel']['flip_timeouts'], 1)
        self.assertNotIn('bad', levels(s))
        self.assertNotIn('warn', levels(s))
        self.assertGreater(len(texts(s, 'info')), base)

    def test_kernel_counters(self):
        log = ('Nov 18 10:00:01 archpc kernel: NVRM: Xid (PCI:0000:01:00): 31, pid=1, MMU Fault\n'
               'Nov 18 10:00:02 archpc kernel: NVRM: Xid (PCI:0000:01:00): 79, pid=1, fell off\n'
               'Nov 18 10:00:03 archpc kernel: nvidia-modeset: ERROR: GPU:0: Flip event timeout on head 0\n'
               'Nov 18 10:00:04 archpc kernel: nvidia-modeset: ERROR: GPU:0: Flip event timeout on head 0\n'
               'Nov 18 10:00:05 archpc kernel: nvidia-modeset: ERROR: GPU:0: Flip event timeout on head 0\n'
               'Nov 18 10:00:06 archpc kernel: Out of memory: Killed process 4242 (game.exe) total-vm:1kB\n'
               'Nov 18 10:00:07 archpc kernel: usb 1-1: new device\n')
        k = self.summary('kern', kernel=log)['kernel']
        self.assertEqual((len(k['xid']), k['flip_timeouts'], k['oom']), (2, 3, 1))

    def test_vram_warning_names_game_mode_only_when_it_is_off(self):
        evs = [ev(10.2, 'vram_warning'), ev(11.5, 'vram_warning')]
        off = self.summary('vo', events=evs, meta={'settings': {'game_mode_on': False}})
        on = self.summary('vn', events=evs, meta={'settings': {'game_mode_on': True}})
        for s in (off, on):
            self.assertTrue(any('memory' in t.lower() for t in texts(s, 'bad')), s['findings'])
            self.assertEqual(s['game_log']['vram_warnings'], 2)
        memory = lambda s: ' '.join(t for t in texts(s, 'bad') if 'memory' in t.lower()).lower()
        self.assertTrue('game mode' in memory(off) or 'bonsai' in memory(off), memory(off))
        self.assertNotIn('game mode', memory(on))
        self.assertNotIn('bonsai', memory(on))

    def test_game_log_counters(self):
        evs = [ev(10.2, 'disconnect'), ev(12.7, 'pso_cache', value='Disabled'),
               ev(13.1, 'present_mode', value='Mailbox'), ev(13.9, 'renderer', value='Vulkan'),
               ev(14.4, 'reflex', value='On')]
        g = self.summary('gl', events=evs)['game_log']
        self.assertEqual(g['disconnects'], 1)
        self.assertTrue(g['pso_cache_off'])
        self.assertEqual(g['vram_warnings'], 0)
        self.assertEqual((g['present_mode'], g['renderer'], g['reflex']), ('Mailbox', 'Vulkan', 'On'))


class Fingerprint(Tmp):
    def fp(self, **kw):
        s = analyze.analyze(str(micro(self.root, f'fp{len(os.listdir(self.root))}', [(10, 300)], **kw)))[0]
        return s

    def test_ambient_changes_keep_the_fingerprint(self):
        a = self.fp()
        b = self.fp(meta={'settings': {'kernel': '7.0.1', 'nvidia_driver': '580.1',
                                       'packages': {'mesa': '26.0', 'wine': '10.0'}}})
        self.assertEqual(len(a['fingerprint']), 8)
        self.assertEqual(a['fingerprint'], b['fingerprint'])
        self.assertEqual(a['chosen'], b['chosen'])
        self.assertNotEqual(a['ambient'], b['ambient'])
        self.assertEqual(b['ambient']['kernel'], '7.0.1')
        self.assertEqual(b['ambient']['nvidia_driver'], '580.1')

    def test_proton_build_is_an_update_not_a_chosen_setting(self):
        # The user keeps Proton on the newest build: a new build must not open a new settings group.
        old = self.fp()
        new = self.fp(meta={'process': {'proton_version': 'GE-Proton10-27'}})
        self.assertEqual(old['fingerprint'], new['fingerprint'])
        self.assertEqual(new['ambient']['proton'], 'GE-Proton10-27')

    def test_chosen_has_the_documented_parts(self):
        c = self.fp(meta={'settings': {'lutris_env': {'AFMF_ENABLE': '1'}}})['chosen']
        for key in ('ini', 'lutris_env', 'sync', 'afmf', 'game_mode', 'system'):
            self.assertIn(key, c)
        self.assertIn('AFMF_ENABLE', c['lutris_env'])
        self.assertFalse([k for k in c['lutris_env'] if k.startswith('MANGOHUD')])

    def test_chosen_settings_change_the_fingerprint(self):
        base = self.fp()['fingerprint']
        variants = {
            'framerate_limit': dict(ini={'framerate_limit': '120'}),
            'renderer_type': dict(ini={'renderer_type': 'DX12'}),
            'upscale': dict(ini={'upscale': 'FSR'}),
            'afmf_loaded': dict(meta={'process': {'afmf_loaded': True}}),
            'lutris AFMF_ENABLE': dict(meta={'settings': {'lutris_env': {'AFMF_ENABLE': '1'}}}),
            'lutris DXVK_ASYNC': dict(meta={'settings': {'lutris_env': {'DXVK_ASYNC': '0'}}}),
            'epp': dict(meta={'settings': {'epp': 'power'}}),
        }
        seen = {base}
        for name, kw in variants.items():
            with self.subTest(name):
                value = self.fp(**kw)['fingerprint']
                self.assertNotEqual(value, base)
                seen.add(value)
        self.assertEqual(len(seen), len(variants) + 1)

    def test_mangohud_and_non_graphics_keys_do_not_change_it(self):
        base = self.fp()['fingerprint']
        variants = {
            'MANGOHUD off': dict(meta={'settings': {'lutris_env': {'MANGOHUD': '0'}}}),
            'MANGOHUD_CONFIGFILE': dict(meta={'settings': {'lutris_env': {'MANGOHUD_CONFIGFILE': '/other.conf'}}}),
            'MANGOHUD_DLSYM': dict(meta={'settings': {'lutris_env': {'MANGOHUD_DLSYM': '1'}}}),
            'key binding': dict(ini={'key_inventory': 'b'}),
            'sound volume': dict(ini={'sound_volume': '10'}),
        }
        for name, kw in variants.items():
            with self.subTest(name):
                self.assertEqual(self.fp(**kw)['fingerprint'], base)


def mk(fp, p99, *, seconds=900, status='ok', basis='real', chosen=None, ambient=None, kind='map', extra_kinds=None,
       avg=None, stut=None):
    k = {'seconds': seconds, 'p99_ms': p99, 'low1_fps': 1000.0 / p99,
         'avg_fps': avg if avg is not None else 1500.0 / p99,
         'stutters_per_10min': stut if stut is not None else p99 / 2}
    kinds = {kind: k}
    kinds.update(extra_kinds or {})
    return {'status': status, 'fingerprint': fp, 'chosen': chosen or {'ini': {'framerate_limit': fp}},
            'ambient': ambient or {'kernel': '6.1', 'nvidia_driver': '570'}, 'frame_basis': basis, 'kinds': kinds}


def group(fp, values, **kw):
    return [mk(fp, v, **kw) for v in values]


METRICS = ('stutters_per_10min', 'p99_ms', 'low1_fps', 'avg_fps')


class Compare(unittest.TestCase):
    def test_no_usable_summary(self):
        self.assertIn('Not enough data', analyze.compare([])['verdict'])
        bad = group('a', [30, 30, 30], status='no frames') + group('b', [20, 20, 20], seconds=599)
        self.assertIn('Not enough data', analyze.compare(bad)['verdict'])

    def test_exactly_600_seconds_is_usable(self):
        r = analyze.compare(group('a', [30, 30, 30], seconds=600) + group('b', [20, 20, 20], seconds=600))
        self.assertIn('metrics', r)

    def test_one_group_is_a_baseline_with_its_count(self):
        r = analyze.compare(group('a', [30, 30.2]))
        self.assertTrue(r['verdict'].startswith('Baseline'), r['verdict'])
        self.assertIn('2 of 3', r['verdict'])
        self.assertNotIn('metrics', r)

    def test_kernel_and_driver_differences_stay_one_group(self):
        s = [mk('a', 30, ambient={'kernel': f'6.{i}', 'nvidia_driver': f'57{i}'}) for i in range(6)]
        self.assertTrue(analyze.compare(s)['verdict'].startswith('Baseline'))

    def test_a_small_group_is_not_enough_in_either_position(self):
        for old, new in ((3, 2), (2, 3), (1, 5)):
            with self.subTest(old=old, new=new):
                r = analyze.compare(group('a', [30] * old) + group('b', [20] * new))
                self.assertIn('Not enough data', r['verdict'])
                digits = re.findall(r'\d+', r['verdict'])
                self.assertIn(str(old), digits)
                self.assertIn(str(new), digits)
                self.assertNotIn('metrics', r)

    def test_short_and_failed_sessions_do_not_count_toward_the_minimum(self):
        new = group('b', [20, 20]) + [mk('b', 20, seconds=300), mk('b', 20, status='no frames')]
        r = analyze.compare(group('a', [30, 30, 30]) + new)
        self.assertIn('Not enough data', r['verdict'])
        self.assertNotIn('metrics', r)

    def test_mixed_frame_bases_cannot_be_compared(self):
        old = group('a', [30, 30, 30])
        for new in (group('b', [20, 20, 20], basis='doubled'),
                    group('b', [20, 20], basis='real') + group('b', [20], basis='doubled')):
            with self.subTest():
                self.assertIn('Cannot compare', analyze.compare(old + new)['verdict'])

    def test_clearly_better_group(self):
        r = analyze.compare(group('a', [30.0, 30.2, 29.8]) + group('b', [20.0, 20.1, 19.9]))
        m = r['metrics']
        self.assertEqual(set(m), set(METRICS))
        for name in METRICS:
            self.assertEqual(m[name]['verdict'], 'better', name)
            self.assertLess(m[name]['low'] if name in ('p99_ms', 'stutters_per_10min') else -m[name]['low'], 0)
        self.assertAlmostEqual(m['p99_ms']['before'], 30.0, places=6)
        self.assertAlmostEqual(m['p99_ms']['after'], 20.0, places=6)
        self.assertAlmostEqual(m['low1_fps']['before'], 1000 / 30.0, places=6)
        self.assertAlmostEqual(m['low1_fps']['after'], 1000 / 20.0, places=6)
        self.assertLess(m['p99_ms']['high'], 0)       # whole 95% range of the change sits below zero
        self.assertGreater(m['low1_fps']['low'], 0)   # and above zero for the fps metric
        self.assertLessEqual(m['p99_ms']['low'], m['p99_ms']['high'])

    def test_clearly_worse_group(self):
        r = analyze.compare(group('a', [20.0, 20.1, 19.9]) + group('b', [30.0, 30.2, 29.8]))
        for name in METRICS:
            self.assertEqual(r['metrics'][name]['verdict'], 'worse', name)
        self.assertGreater(r['metrics']['p99_ms']['low'], 0)
        self.assertLess(r['metrics']['low1_fps']['high'], 0)

    def test_overlapping_noisy_groups_show_no_clear_change(self):
        r = analyze.compare(group('a', [20, 30, 25, 22, 28]) + group('b', [24, 29, 21, 27, 26]))
        for name in METRICS:
            self.assertEqual(r['metrics'][name]['verdict'], 'no clear change', name)
        self.assertLess(r['metrics']['p99_ms']['low'], 0)
        self.assertGreater(r['metrics']['p99_ms']['high'], 0)

    def test_a_range_that_excludes_zero_is_not_enough_when_the_change_is_small_next_to_the_spread(self):
        # old: 40 sessions at 20 ms and one outlier at 100 (spread 80); new: 41 sessions at 21 ms.
        # The median never moves, so the range is [1, 1]: it excludes 0, but 1 < 80/2.
        r = analyze.compare(group('a', [20.0] * 40 + [100.0]) + group('b', [21.0] * 41))
        m = r['metrics']['p99_ms']
        self.assertEqual((m['before'], m['after']), (20.0, 21.0))
        self.assertGreater(m['low'], 0)
        self.assertEqual(m['verdict'], 'no clear change')

    def test_the_bootstrap_is_deterministic(self):
        s = group('a', [20, 30, 25, 22, 28]) + group('b', [24, 29, 21, 27, 26])
        a, b = analyze.compare(s), analyze.compare(s)
        for name in METRICS:
            self.assertEqual((a['metrics'][name]['low'], a['metrics'][name]['high']),
                             (b['metrics'][name]['low'], b['metrics'][name]['high']))

    def test_latest_group_is_compared_with_the_group_before_it(self):
        s = group('a', [50, 50, 50]) + group('b', [30, 30, 30]) + group('c', [20, 20, 20])
        r = analyze.compare(s)
        self.assertEqual((r['metrics']['p99_ms']['before'], r['metrics']['p99_ms']['after']), (30, 20))
        self.assertEqual(r['changed'], {'ini.framerate_limit': ['b', 'c']})

    def test_a_returning_setting_does_not_merge_with_its_earlier_group(self):
        s = group('a', [20, 20, 20]) + group('b', [30, 30, 30]) + group('a', [20, 20, 20])
        r = analyze.compare(s)
        self.assertEqual((r['metrics']['p99_ms']['before'], r['metrics']['p99_ms']['after']), (30, 20))
        self.assertEqual(r['metrics']['p99_ms']['verdict'], 'better')

    def test_changed_and_updates_list_old_and_new_values(self):
        old = [mk('a', 30, chosen={'ini': {'framerate_limit': '60'}, 'proton': 'P10'},
                  ambient={'kernel': '6.1', 'nvidia_driver': '570'}) for _ in range(3)]
        new = [mk('b', 20, chosen={'ini': {'framerate_limit': '120'}, 'proton': 'P10'},
                  ambient={'kernel': '6.2', 'nvidia_driver': '570'}) for _ in range(3)]
        r = analyze.compare(old + new)
        self.assertEqual(r['changed'], {'ini.framerate_limit': ['60', '120']})
        self.assertEqual(r['updates'], {'kernel': ['6.1', '6.2']})

    def test_only_the_busiest_kind_is_compared_and_short_sessions_in_it_are_ignored(self):
        def s(fp, map_p99, hide_p99, map_seconds=3000):
            return mk(fp, map_p99, seconds=map_seconds,
                      extra_kinds={'hideout': {'seconds': 900, 'p99_ms': hide_p99, 'low1_fps': 1000 / hide_p99,
                                               'avg_fps': 100.0, 'stutters_per_10min': 1.0}})
        old = [s('a', 30, 10) for _ in range(3)]
        new = [s('b', 20, 40), s('b', 21, 40), s('b', 22, 40), s('b', 1, 40, map_seconds=500)]
        r = analyze.compare(old + new)
        m = r['metrics']['p99_ms']
        self.assertEqual((m['before'], m['after']), (30, 21))   # the 500 s session (p99 1) is dropped
        self.assertEqual(m['verdict'], 'better')


class EndToEnd(SharedTmp):
    def test_real_sessions_are_summarised_loaded_and_compared(self):
        sessions = Path(self.root) / 'sessions'
        sessions.mkdir()
        plan = [('2026-11-01_a', 80, '60', '6.1'), ('2026-11-02_a', 80, '60', '6.2'), ('2026-11-03_a', 80, '60', '6.3'),
                ('2026-11-04_a', 40, '120', '6.3'), ('2026-11-05_a', 40, '120', '6.4'), ('2026-11-06_a', 40, '120', '6.5')]
        for name, ms, cap, kernel in reversed(plan):   # written out of order on purpose
            micro(sessions, name, [(ms, int(620000 / ms))], area='Map_E2E', ini={'framerate_limit': cap},
                  meta={'settings': {'kernel': kernel}})
            analyze.write_summary(str(sessions / name))
        loaded = analyze.summaries(str(sessions))
        self.assertEqual([s['session'] for s in loaded], [p[0] for p in plan])
        self.assertEqual(len({s['fingerprint'] for s in loaded[:3]}), 1)
        self.assertNotEqual(loaded[2]['fingerprint'], loaded[3]['fingerprint'])
        self.assertAlmostEqual(loaded[0]['kinds']['map']['seconds'], 620.0, delta=0.2)
        r = analyze.compare(loaded)
        m = r['metrics']
        self.assertEqual((m['p99_ms']['before'], m['p99_ms']['after']), (80, 40))
        self.assertEqual(m['p99_ms']['verdict'], 'better')
        self.assertEqual(m['low1_fps']['verdict'], 'better')
        self.assertEqual(m['avg_fps']['verdict'], 'better')
        self.assertEqual(m['stutters_per_10min']['verdict'], 'no clear change')
        self.assertEqual({k: [str(x) for x in v] for k, v in r['changed'].items()}, {'ini.framerate_limit': ['60', '120']})
        self.assertIn('kernel', r['updates'])


class Candidates(Tmp):
    def cand(self, today='2026-11-18', *, gpu=40, slow=False, meta=None, ini=None):
        kinds = {20: 'slow', 21: 'slow'} if slow else {}
        path = sec_session(self.root, f'c{len(os.listdir(self.root))}', first=7, last=36, kinds=kinds, gpu=gpu,
                           meta=meta, ini=ini, load_off=5.4, load_s=1.0, zone_off=3.0)
        summary = analyze.analyze(str(path))[0]
        mt = json.loads((path / 'meta.json').read_text())
        return analyze.candidates(summary, mt, today)

    def ids(self, items):
        return [c['id'] for c in items]

    def test_items_have_the_documented_fields(self):
        items = self.cand(meta={'settings': {'game_mode_on': False}})
        self.assertTrue(items)
        for c in items:
            for key in ('id', 'change', 'judged_by', 'evidence'):
                self.assertIn(key, c)

    def test_everything_at_once_and_no_pin_suggestion(self):
        everything = self.cand('2026-12-05', meta={'settings': {'game_mode_on': False,
                                                                'lutris_ignored_env': ['FOO_BAR', 'DXVK_LOG_LEVEL', 'WINEFSYNC']},
                                                   'process': {'proton_version': 'GE-Proton10-27', 'sync': 'ntsync'}})
        self.assertNotIn('pin-proton', self.ids(everything))
        moved = next(c['change'] for c in everything if c['id'] == 'ignored-lutris-env')
        self.assertIn('FOO_BAR', moved)
        self.assertNotIn('DXVK_LOG_LEVEL', moved)      # does nothing with the Vulkan renderer
        self.assertNotIn('WINEFSYNC', moved)           # ntsync is in use
        self.assertTrue({'afmf', 'ignored-lutris-env', 'fps-cap', 'game-mode', 'proton-ge11'} <= set(self.ids(everything)))

    def test_afmf_waits_for_december_and_only_when_not_loaded(self):
        self.assertNotIn('afmf', self.ids(self.cand('2026-11-30')))
        self.assertIn('afmf', self.ids(self.cand('2026-12-01')))
        self.assertIn('afmf', self.ids(self.cand('2027-01-15')))
        self.assertNotIn('afmf', self.ids(self.cand('2026-12-05', meta={'process': {'afmf_loaded': True}})))

    def test_ignored_lutris_env_names_the_variables(self):
        self.assertNotIn('ignored-lutris-env', self.ids(self.cand()))
        items = self.cand(meta={'settings': {'lutris_ignored_env': ['PROTON_FOO', 'FOO_BAR']}})
        change = next(c for c in items if c['id'] == 'ignored-lutris-env')['change']
        self.assertIn('PROTON_FOO', change)
        self.assertIn('FOO_BAR', change)

    def test_fps_cap_needs_a_cap_few_slow_seconds_and_a_idle_card(self):
        self.assertIn('fps-cap', self.ids(self.cand(gpu=40)))
        self.assertNotIn('fps-cap', self.ids(self.cand(gpu=90)))
        self.assertNotIn('fps-cap', self.ids(self.cand(gpu=40, slow=True)))   # 2 of 30 seconds slow
        self.assertNotIn('fps-cap', self.ids(self.cand(gpu=40, ini={'framerate_limit_enabled': 'false'})))

    def test_game_mode_and_proton_ge11(self):
        self.assertNotIn('game-mode', self.ids(self.cand()))
        self.assertIn('game-mode', self.ids(self.cand(meta={'settings': {'game_mode_on': False}})))
        self.assertIn('proton-ge11', self.ids(self.cand(meta={'process': {'proton_version': 'GE-Proton10-27'}})))
        self.assertNotIn('proton-ge11', self.ids(self.cand(meta={'process': {'proton_version': 'GE-Proton11-12'}})))


class Report(SharedTmp):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.path = build_main(cls.root, 'report-session', load1='A <b>&</b> Test')
        cls.summary, cls.detail = analyze.analyze(str(cls.path))
        cls.meta = json.loads((cls.path / 'meta.json').read_text())
        cls.suggestions = analyze.candidates(cls.summary, cls.meta, '2026-12-05') + [
            {'id': 'x', 'change': 'Cap at 60 <fps> & test', 'judged_by': 'test', 'evidence': 'none'}]
        cls.out = analyze.report(str(cls.path), cls.summary, cls.detail, analyze.compare([cls.summary]), cls.suggestions)
        cls.page = Path(cls.out).read_text()

    @staticmethod
    def has(page, text):
        return any(h in page for h in (htmllib.escape(text), htmllib.escape(text, quote=False)))

    def test_report_is_written_into_the_session_directory(self):
        self.assertEqual(Path(self.out).resolve(), (self.path / 'report.html').resolve())

    def test_report_is_self_contained(self):
        p = self.page
        self.assertNotIn('http://', p)
        self.assertNotIn('https://', p)
        self.assertIsNone(re.search(r'<script[^>]*\ssrc\s*=', p, re.I))
        self.assertIsNone(re.search(r'<link[^>]*\shref\s*=', p, re.I))
        self.assertIsNone(re.search(r'<img[^>]*\ssrc\s*=\s*["\']?(?!data:)', p, re.I))
        self.assertIn('<svg', p)

    def test_report_shows_the_headline_numbers(self):
        o = self.summary['overall']
        for label, value in (('avg', o['avg_fps']), ('low1', o['low1_fps']),
                             ('stutters/10min', self.summary['stutters_per_10min'])):
            forms = {f'{value:.0f}', f'{value:.1f}', f'{value:.2f}', str(value)}
            self.assertTrue(any(f in self.page for f in forms), (label, forms))

    def test_findings_and_suggestions_are_listed_and_escaped(self):
        for f in self.summary['findings']:
            self.assertTrue(self.has(self.page, f['text']), f['text'])
        for c in self.suggestions:
            self.assertTrue(self.has(self.page, c['change']), c['change'])
        self.assertNotIn('<fps>', self.page)

    def test_area_names_are_escaped(self):
        self.assertNotIn('A <b>', self.page)
        self.assertIn('A &lt;b&gt;&amp;&lt;/b&gt; Test', self.page)

    def test_report_without_frames_has_no_charts_and_does_not_raise(self):
        path = build(self.root, 'empty-session', events=[ev(0.0, 'start')], end=10)
        s, d = analyze.analyze(str(path))
        self.assertIsNone(s['overall'])
        out = analyze.report(str(path), s, d, analyze.compare([s]), [])
        page = Path(out).read_text()
        self.assertNotIn('http://', page)
        for f in s['findings']:
            self.assertTrue(self.has(page, f['text']))


# ---------------------------------------------------------------- fingerprint: kernel command line and sectioned config
CMDLINE = ('initrd=\\abc\\7.3.4-arch1-1\\initrd nvme_load=YES nowatchdog rw split_lock_detect=off '
           'root=UUID=1234-5678 systemd.machine_id=0123456789abcdef')
SECTIONED = """[DISPLAY]
renderer_type=Vulkan
some_new_graphics_option=3
framerate_limit=60
framerate_limit_enabled=true
[SOUND]
master_volume=50
[GENERAL]
engine_multithreading_mode=enabled
enable_subtitles=true
[NETWORKING]
networking_type=predictive
"""
FLAT = ('framerate_limit=60\nframerate_limit_enabled=true\nrenderer_type=Vulkan\nupscale=NIS\n'
        'key_inventory=i\nsome_unknown_ui_thing=1\n')


class FingerprintCmdlineAndSections(Tmp):
    def summ(self, text=SECTIONED, cmdline=CMDLINE, bom=False):
        name = f'fc{len(os.listdir(self.root))}'
        path = micro(self.root, name, [(10, 300)], meta={'settings': {'cmdline': cmdline}})
        data = text.encode()
        if bom:
            data = b'\xef\xbb\xbf' + data
        (Path(path) / 'config.ini').write_bytes(data)
        return analyze.analyze(str(path))[0]

    def fp(self, *args, **kw):
        return self.summ(*args, **kw)['fingerprint']

    # ---- A1
    def test_kernel_update_in_the_initrd_path_keeps_the_fingerprint(self):
        newer = CMDLINE.replace('7.3.4-arch1-1', '7.3.5-arch1-1')
        self.assertNotEqual(newer, CMDLINE)
        self.assertEqual(self.fp(cmdline=CMDLINE), self.fp(cmdline=newer))

    def test_other_kernel_parameters_change_the_fingerprint(self):
        base = self.fp()
        variants = {
            'split_lock_detect removed': CMDLINE.replace(' split_lock_detect=off', ''),
            'mitigations added': CMDLINE + ' mitigations=off',
            'value changed': CMDLINE.replace('nvme_load=YES', 'nvme_load=NO'),
        }
        seen = {base}
        for name, cmd in variants.items():
            with self.subTest(name):
                self.assertNotEqual(cmd, CMDLINE)
                value = self.fp(cmdline=cmd)
                self.assertNotEqual(value, base)
                seen.add(value)
        self.assertEqual(len(seen), len(variants) + 1)

    # ---- A2
    def test_any_display_key_changes_it_even_an_unknown_one(self):
        base = self.fp()
        for old, new in [('some_new_graphics_option=3', 'some_new_graphics_option=4'),
                         ('renderer_type=Vulkan', 'renderer_type=DX12'),
                         ('framerate_limit=60', 'framerate_limit=90')]:
            with self.subTest(old):
                self.assertNotEqual(self.fp(SECTIONED.replace(old, new)), base)

    def test_general_and_networking_keys_change_it(self):
        base = self.fp()
        for old, new in [('engine_multithreading_mode=enabled', 'engine_multithreading_mode=disabled'),
                         ('networking_type=predictive', 'networking_type=lockstep')]:
            with self.subTest(old):
                self.assertNotEqual(self.fp(SECTIONED.replace(old, new)), base)

    def test_sound_and_subtitles_do_not_change_it(self):
        base = self.fp()
        for old, new in [('master_volume=50', 'master_volume=10'), ('enable_subtitles=true', 'enable_subtitles=false')]:
            with self.subTest(old):
                self.assertEqual(self.fp(SECTIONED.replace(old, new)), base)

    def test_byte_order_mark_changes_nothing(self):
        plain, bom = self.summ(), self.summ(bom=True)
        self.assertEqual(plain['fingerprint'], bom['fingerprint'])
        self.assertEqual(plain['fps_cap'], 60)
        self.assertEqual(bom['fps_cap'], 60)
        changed = self.summ(SECTIONED.replace('some_new_graphics_option=3', 'some_new_graphics_option=4'), bom=True)
        self.assertNotEqual(changed['fingerprint'], bom['fingerprint'])  # the BOM does not hide the DISPLAY section

    def test_flat_file_without_sections_still_reacts_to_graphics_keys(self):
        base = self.fp(FLAT)
        for old, new in [('framerate_limit=60', 'framerate_limit=120'), ('renderer_type=Vulkan', 'renderer_type=DX12'),
                         ('upscale=NIS', 'upscale=FSR')]:
            with self.subTest(old):
                self.assertNotEqual(self.fp(FLAT.replace(old, new)), base)

    def test_flat_file_ignores_unknown_non_graphics_keys(self):
        base = self.fp(FLAT)
        self.assertEqual(self.fp(FLAT.replace('some_unknown_ui_thing=1', 'some_unknown_ui_thing=2')), base)
        self.assertEqual(self.fp(FLAT.replace('key_inventory=i', 'key_inventory=b')), base)
        self.assertEqual(self.summ(FLAT)['fps_cap'], 60)


if __name__ == '__main__':
    unittest.main()
