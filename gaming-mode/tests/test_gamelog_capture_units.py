"""Unit tests for gamelog_lib.capture: wait_for_game, wait_until_gone, GpuStream, Sampler.cpu."""
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

_ROOT = tempfile.mkdtemp(prefix='gamelog-capunit.')
for _k, _v in {
    'HOME': f'{_ROOT}/home', 'XDG_STATE_HOME': f'{_ROOT}/xdg-state',
    'XDG_CONFIG_HOME': f'{_ROOT}/xdg-config', 'XDG_RUNTIME_DIR': f'{_ROOT}/xdg-run',
    'GAMELOG_STATE': f'{_ROOT}/state', 'GAMELOG_PROC': f'{_ROOT}/proc', 'GAMELOG_SYS': f'{_ROOT}/sys',
    'GAMELOG_GAME_DIR': f'{_ROOT}/game', 'GAMELOG_CLIENT_LOG': f'{_ROOT}/game/Client.txt',
    'GAMELOG_INI': f'{_ROOT}/game/production_Config.ini', 'GAMELOG_LUTRIS_GAMES': f'{_ROOT}/lutris',
    'GAMELOG_MANGO_CONF': f'{_ROOT}/mango/MangoHud.conf', 'GAMELOG_NOTIFY': f'{_ROOT}/no-such-notifier',
}.items():
    os.environ[_k] = _v

from gamelog_lib import capture  # noqa: E402


def tearDownModule():
    shutil.rmtree(_ROOT, True)


class FakeTime:
    """Fake clock: sleep() advances monotonic(). Aborts runaway loops."""
    def __init__(self):
        self.now = 1000.0
        self.t0 = self.now

    def monotonic(self):
        return self.now

    def sleep(self, s):
        self.now += s if s and s > 0 else 0.001
        if self.now - self.t0 > 5000:
            raise RuntimeError('runaway loop in fake time')

    def time(self):
        return self.now

    @property
    def elapsed(self):
        return self.now - self.t0


class ClockCase(unittest.TestCase):
    def setUp(self):
        self.ft = FakeTime()
        for name, val in (('time', self.ft), ('INTERVAL', 1.0)):
            p = mock.patch.object(capture, name, val)
            p.start()
            self.addCleanup(p.stop)

    def patch(self, name, val):
        p = mock.patch.object(capture, name, val)
        p.start()
        self.addCleanup(p.stop)


class WaitForGame(ClockCase):
    def test_returns_pid_immediately(self):
        self.patch('find_game', lambda: 4242)
        self.patch('launching', lambda: True)
        self.assertEqual(capture.wait_for_game(30), 4242)
        self.assertLess(self.ft.elapsed, 1.5)

    def test_returns_pid_when_it_appears_within_seconds(self):
        self.patch('find_game', lambda: 77 if self.ft.elapsed >= 6 else None)
        self.patch('launching', lambda: False)
        self.assertEqual(capture.wait_for_game(30), 77)
        self.assertLess(self.ft.elapsed, 10)

    def test_default_gives_up_after_seconds_even_with_launcher_running(self):
        self.patch('START_WAIT_MAX', 100.0)
        self.patch('find_game', lambda: None)
        self.patch('launching', lambda: True)
        self.assertIsNone(capture.wait_for_game(5))
        self.assertGreaterEqual(self.ft.elapsed, 5)
        self.assertLess(self.ft.elapsed, 10)

    def test_default_does_not_see_game_that_appears_after_seconds_with_launcher(self):
        self.patch('START_WAIT_MAX', 100.0)
        self.patch('find_game', lambda: 9 if self.ft.elapsed >= 20 else None)
        self.patch('launching', lambda: self.ft.elapsed < 20)
        self.assertIsNone(capture.wait_for_game(5))

    def test_patient_waits_past_seconds_while_launcher_runs(self):
        self.patch('START_WAIT_MAX', 100.0)
        self.patch('find_game', lambda: 9 if self.ft.elapsed >= 20 else None)
        self.patch('launching', lambda: self.ft.elapsed < 20)
        self.assertEqual(capture.wait_for_game(5, patient=True), 9)
        self.assertGreaterEqual(self.ft.elapsed, 20)

    def test_patient_returns_none_after_seconds_when_no_launcher(self):
        self.patch('START_WAIT_MAX', 100.0)
        self.patch('find_game', lambda: None)
        self.patch('launching', lambda: False)
        self.assertIsNone(capture.wait_for_game(5, patient=True))
        self.assertGreaterEqual(self.ft.elapsed, 5)
        self.assertLess(self.ft.elapsed, 10)

    def test_patient_stops_when_launcher_ends_without_game(self):
        self.patch('START_WAIT_MAX', 100.0)
        self.patch('find_game', lambda: None)
        self.patch('launching', lambda: self.ft.elapsed < 30)
        self.assertIsNone(capture.wait_for_game(5, patient=True))
        self.assertGreaterEqual(self.ft.elapsed, 30)
        self.assertLess(self.ft.elapsed, 36)

    def test_patient_is_capped_by_start_wait_max(self):
        self.patch('START_WAIT_MAX', 50.0)
        self.patch('find_game', lambda: None)
        self.patch('launching', lambda: True)
        self.assertIsNone(capture.wait_for_game(5, patient=True))
        self.assertGreaterEqual(self.ft.elapsed, 50)
        self.assertLess(self.ft.elapsed, 56)


class WaitUntilGone(ClockCase):
    def test_waits_for_slow_start_then_for_exit(self):
        self.patch('START_WAIT', 5.0)
        self.patch('START_WAIT_MAX', 100.0)
        up, down = 8.0, 14.0  # game appears after START_WAIT, launcher runs until then
        seen = []

        def find():
            if up <= self.ft.elapsed < down:
                seen.append(self.ft.elapsed)
                return 5150
            return None
        self.patch('find_game', find)
        self.patch('launching', lambda: self.ft.elapsed < up)
        capture.wait_until_gone()
        self.assertTrue(seen, 'loop never saw the game: gave up before slow start')
        self.assertGreaterEqual(self.ft.elapsed, down)
        self.assertLess(self.ft.elapsed, down + 6)

    def test_returns_after_start_wait_when_no_game_and_no_launcher(self):
        self.patch('START_WAIT', 5.0)
        self.patch('START_WAIT_MAX', 100.0)
        self.patch('find_game', lambda: None)
        self.patch('launching', lambda: False)
        capture.wait_until_gone()
        self.assertLess(self.ft.elapsed, 12)


class GpuStreamCase(unittest.TestCase):
    def make(self):
        g = capture.GpuStream.__new__(capture.GpuStream)
        g.latest, g.seen, g.proc, g.restarts = None, 0.0, None, 0
        return g

    def line(self, n=14, pad=' '):
        return ','.join(f'{pad}v{i}{pad}' for i in range(n)) + '\n'


class GpuPump(GpuStreamCase):
    def test_14_fields_become_latest_stripped(self):
        g = self.make()
        g.pump(mock.Mock(stdout=iter([self.line(14)])))
        self.assertEqual(list(g.latest), [f'v{i}' for i in range(14)])

    def test_wrong_field_counts_are_ignored_and_keep_previous(self):
        g = self.make()
        g.pump(mock.Mock(stdout=iter([self.line(14), self.line(13), self.line(15), 'garbage\n', '\n'])))
        self.assertEqual(list(g.latest), [f'v{i}' for i in range(14)])

    def test_wrong_count_alone_leaves_no_sample(self):
        g = self.make()
        g.pump(mock.Mock(stdout=iter([self.line(13), self.line(15)])))
        self.assertIsNone(g.latest)

    def test_newer_valid_line_replaces_older(self):
        g = self.make()
        new = ','.join(f'n{i}' for i in range(14)) + '\n'
        g.pump(mock.Mock(stdout=iter([self.line(14), new])))
        self.assertEqual(list(g.latest), [f'n{i}' for i in range(14)])


class GpuValues(GpuStreamCase):
    def fresh(self, sample):
        g = self.make()
        g.latest = sample
        g.seen = capture.time.monotonic()
        return g

    def test_no_sample_gives_14_empty_strings(self):
        g = self.make()
        g.seen = capture.time.monotonic()
        self.assertEqual(g.values(), [''] * 14)
        self.assertEqual(len(capture.GPU_FIELDS), 14)

    def test_translation_rules(self):
        sample = ['Active', 'Not Active', '[N/A]', '[Not Supported]', '55', 'P2', 'active',
                  'Not Active ', '0', '', 'N/A', '1', '[', 'x[y']
        out = self.fresh(sample).values()
        self.assertEqual(len(out), 14)
        self.assertEqual(out[0], '1')
        self.assertEqual(out[1], '0')
        self.assertEqual(out[2], '')
        self.assertEqual(out[3], '')
        self.assertEqual(out[4], '55')
        self.assertEqual(out[5], 'P2')
        self.assertEqual(out[6], 'active')      # case-sensitive: passes through
        self.assertEqual(out[8], '0')
        self.assertEqual(out[10], 'N/A')        # no bracket: unchanged
        self.assertEqual(out[11], '1')
        self.assertEqual(out[12], '')
        self.assertEqual(out[13], 'x[y')        # bracket not at start: unchanged


CPU_A = """cpu  100 0 100 800 0 0 0 0 0 0
cpu0 50 0 50 400 0 0 0 0 0 0
cpu1 50 0 50 400 0 0 0 0 0 0
cpu2 0 0 0 1000 0 0 0 0 0 0
intr 9999 1 2 3
ctxt 5000
btime 1700000000
processes 400
cpu9 1 1 1 1
"""
# deltas vs A: aggregate busy 200 / total 400 -> 50%; cpu0 busy 30/total 100 -> 30%;
# cpu1 busy 100/total 100 -> 100%; cpu2 busy 0/total 100 -> 0%
CPU_B = """cpu  200 0 200 900 100 0 0 0 0 0
cpu0 80 0 50 460 10 0 0 0 0 0
cpu1 150 0 50 400 0 0 0 0 0 0
cpu2 0 0 0 1100 0 0 0 0 0 0
intr 99999 1 2 3
ctxt 6000
btime 1700000000
processes 500
cpu9 5 5 5 5
"""


class SamplerCpu(unittest.TestCase):
    def run_two(self, a, b):
        s = capture.Sampler.__new__(capture.Sampler)
        s.prev = {}
        with mock.patch.object(capture, 'read', lambda path, *x, **k: a):
            s.cpu(1.0)
        with mock.patch.object(capture, 'read', lambda path, *x, **k: b):
            return s.cpu(2.0)

    def test_total_and_per_core_percentages(self):
        total, cores = self.run_two(CPU_A, CPU_B)
        self.assertAlmostEqual(float(total), 50.0, delta=0.1)
        parts = cores.split('|')
        self.assertEqual(len(parts), 3)  # cpu0..cpu2 only; cpu9 after other lines ignored
        self.assertAlmostEqual(float(parts[0]), 30.0, delta=0.1)
        self.assertAlmostEqual(float(parts[1]), 100.0, delta=0.1)
        self.assertAlmostEqual(float(parts[2]), 0.0, delta=0.1)

    def test_iowait_counts_as_idle(self):
        a = "cpu  0 0 0 0 0 0 0 0\ncpu0 0 0 0 0 0 0 0 0\nintr 1\n"
        b = "cpu  0 0 0 50 50 0 0 0\ncpu0 0 0 0 50 50 0 0 0\nintr 2\n"
        total, cores = self.run_two(a, b)
        self.assertAlmostEqual(float(total), 0.0, delta=0.1)
        self.assertAlmostEqual(float(cores), 0.0, delta=0.1)

    def test_irq_softirq_steal_count_as_busy(self):
        a = "cpu  0 0 0 0 0 0 0 0\ncpu0 0 0 0 0 0 0 0 0\nintr 1\n"
        b = "cpu  0 0 0 50 0 10 20 20\ncpu0 0 0 0 50 0 10 20 20\nintr 2\n"
        total, cores = self.run_two(a, b)
        self.assertAlmostEqual(float(total), 50.0, delta=0.1)
        self.assertAlmostEqual(float(cores), 50.0, delta=0.1)

    def test_single_core_has_one_entry_and_no_separator(self):
        a = "cpu  0 0 0 0 0 0 0 0\ncpu0 0 0 0 0 0 0 0 0\nintr 1\n"
        b = "cpu  50 0 0 50 0 0 0 0\ncpu0 50 0 0 50 0 0 0 0\nintr 2\n"
        total, cores = self.run_two(a, b)
        self.assertNotIn('|', cores)
        self.assertAlmostEqual(float(cores), 50.0, delta=0.1)


def _load_cli():
    from importlib.machinery import SourceFileLoader
    from importlib.util import module_from_spec, spec_from_loader
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'gamelog')
    spec = spec_from_loader('gamelog_cli', SourceFileLoader('gamelog_cli', path))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GamelogCli(unittest.TestCase):
    """The compare and next printouts of the gamelog command."""

    def run_cli(self, *args):
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.cli.main(['gamelog', *args])
        return code, out.getvalue()

    def setUp(self):
        self.cli = _load_cli()

    def test_compare_lists_each_changed_setting_and_update(self):
        result = {'verdict': 'better', 'changed': {'fps_limit': (120, 144)}, 'updates': {'proton': ('9.0', '10.0')}}
        with mock.patch.object(self.cli.analyze, 'summaries', return_value=[]), \
                mock.patch.object(self.cli.analyze, 'compare', return_value=result):
            code, text = self.run_cli('compare')
        self.assertEqual(code, 0)
        self.assertEqual(text.splitlines(), ['better', '  Settings changed: fps_limit: 120 -> 144',
                                             '  Updates in between: proton: 9.0 -> 10.0'])

    def next_text(self, comparison):
        suggestion = {'id': 'fps-cap', 'change': 'Lower the cap', 'evidence': 'e', 'judged_by': 'j'}
        with mock.patch.object(self.cli, 'latest', return_value=Path('/nonexistent')), \
                mock.patch.object(self.cli, 'finish', return_value=(None, None, comparison, [suggestion])):
            return self.run_cli('next')[1]

    def test_next_without_a_ready_flag_keeps_collecting_and_names_no_next_step(self):
        text = self.next_text({'current_minutes': 12, 'kind': 'map'})
        self.assertIn('Collecting: 12 of', text)
        self.assertNotIn('NEXT', text)

    def test_next_when_ready_names_the_first_suggestion(self):
        text = self.next_text({'ready': True})
        self.assertNotIn('Collecting', text)
        self.assertIn('NEXT fps-cap: Lower the cap', text)


if __name__ == '__main__':
    unittest.main()
