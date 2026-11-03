"""Behavior tests for hw-log with fake /sys, /proc, sensors and nvidia-smi. Run: python3 -m unittest linux/tests/test_hw_log.py"""

import csv
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "hw-log"
HEADER = (
    "ts,cpu_util_pct,cpu_mhz_avg,cpu_pkg_w,tctl_c,tccd1_c,load1,mem_used_mb,"
    "gpu_util_pct,gpu_temp_c,gpu_w,gpu_mem_mb,nvme_c,fan1_rpm,fan5_rpm,fan6_rpm,top3_cpu_pct"
)
COLS = HEADER.split(",")
MAX_RANGE = 262143328850

FAKE_SENSORS = """#!/bin/bash
cat "$FAKE_DIR/sensors.json"
"""
FAKE_NVIDIA = """#!/bin/bash
if [ -f "$FAKE_DIR/next_stat" ]; then cp "$FAKE_DIR/next_stat" "$HW_LOG_PROC/stat"; fi
if [ -f "$FAKE_DIR/next_energy" ]; then cp "$FAKE_DIR/next_energy" "$HW_LOG_SYS/class/powercap/intel-rapl:0/energy_uj"; fi
if [ -f "$FAKE_DIR/gpu_fail" ]; then exit 1; fi
cat "$FAKE_DIR/gpu.txt"
"""
BASE_STAT = (1000, 0, 500, 5000, 100, 0, 0, 0)
SENSORS_FULL = """{
 "k10temp-pci-00c3": {"Adapter": "PCI adapter",
   "Tctl": {"temp1_input": 45.16}, "Tccd1": {"temp3_input": 51.04}},
 "nvme-pci-0200": {"Composite": {"temp1_input": 38.04}},
 "nct6687-isa-0a20": {"fan1": {"fan1_input": 1234.56}, "fan5": {"fan5_input": 800.0}, "fan6": {"fan6_input": 650.0}}
}"""


def stat_line(vals):
    user, nice, system, idle, iowait, irq, softirq, steal = vals
    return f"cpu  {user} {nice} {system} {idle} {iowait} {irq} {softirq} {steal} 0 0\ncpu0 1 2 3 4 5 6 7 8 0 0\n"


class HwLog(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.base = base
        self.fake = base / "fake"
        self.fake.mkdir()
        bindir = base / "bin"
        bindir.mkdir()
        for name, body in (("sensors", FAKE_SENSORS), ("nvidia-smi", FAKE_NVIDIA)):
            p = bindir / name
            p.write_text(body)
            p.chmod(0o755)
        self.sys = base / "sys"
        rapl = self.sys / "class" / "powercap" / "intel-rapl:0"
        rapl.mkdir(parents=True)
        self.energy = rapl / "energy_uj"
        self.energy.write_text("5000000\n")
        (rapl / "max_energy_range_uj").write_text(f"{MAX_RANGE}\n")
        self.proc = base / "proc"
        self.proc.mkdir()
        (self.proc / "stat").write_text(stat_line(BASE_STAT))
        (self.proc / "cpuinfo").write_text(
            "processor\t: 0\ncpu MHz\t\t: 4000.000\n\nprocessor\t: 1\ncpu MHz\t\t: 3000.000\n\n"
            "processor\t: 2\ncpu MHz\t\t: 3001.000\n"
        )
        (self.proc / "meminfo").write_text(
            "MemTotal:       32768000 kB\nMemFree:         1000000 kB\nMemAvailable:   20000000 kB\n"
        )
        (self.proc / "loadavg").write_text("0.69 0.50 0.40 1/100 123\n")
        (self.fake / "sensors.json").write_text(SENSORS_FULL)
        (self.fake / "gpu.txt").write_text("12, 55, 80.25, 2048\n")
        self.out = base / "out.csv"
        self.path = f"{bindir}:{os.environ['PATH']}"

    def tearDown(self):
        self.tmp.cleanup()

    def set_next(self, stat_delta=None, energy=None):
        if stat_delta is not None:
            vals = tuple(a + b for a, b in zip(BASE_STAT, stat_delta))
            (self.fake / "next_stat").write_text(stat_line(vals))
        if energy is not None:
            (self.fake / "next_energy").write_text(f"{energy}\n")

    def run_script(self, samples=2, args=None):
        env = {
            **os.environ,
            "PATH": self.path,
            "FAKE_DIR": str(self.fake),
            "HW_LOG_SYS": str(self.sys),
            "HW_LOG_PROC": str(self.proc),
            "HW_LOG_INTERVAL": "0.1",
            "HW_LOG_SAMPLES": str(samples),
        }
        args = [str(self.out)] if args is None else args
        return subprocess.run(
            ["nice", "-n", "19", str(SCRIPT), *args],
            env=env, capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL,
        )

    def rows(self):
        with open(self.out, newline="") as f:
            return list(csv.reader(f))

    def last_row(self):
        r = self.rows()[-1]
        self.assertEqual(len(r), 17, r)
        return dict(zip(COLS, r))

    def test_header_written_once_on_new_file(self):
        r = self.run_script(samples=2)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = self.out.read_text().splitlines()
        self.assertEqual(lines[0], HEADER)
        self.assertEqual(sum(1 for l in lines if l.startswith("ts,")), 1)

    def test_header_written_to_empty_existing_file(self):
        self.out.write_text("")
        self.run_script(samples=1)
        self.assertEqual(self.out.read_text().splitlines()[0], HEADER)

    def test_no_header_when_appending_to_existing_file(self):
        self.out.write_text("old,content\n")
        r = self.run_script(samples=2)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = self.out.read_text().splitlines()
        self.assertEqual(lines[0], "old,content")
        self.assertEqual(len(lines), 3)
        self.assertFalse(any(l.startswith("ts,") for l in lines))

    def test_two_samples_two_rows_exit_zero(self):
        r = self.run_script(samples=2)
        self.assertEqual(r.returncode, 0, r.stderr)
        rows = self.rows()
        self.assertEqual(len(rows), 3)
        for row in rows[1:]:
            self.assertEqual(len(row), 17, row)
            self.assertTrue(row[0])

    def test_first_sample_zero_deltas_gives_zero_util(self):
        self.run_script(samples=1)
        row = self.last_row()
        self.assertEqual(float(row["cpu_util_pct"]), 0.0)

    def test_cpu_util_iowait_in_total_not_busy(self):
        # busy +300 (user 200, system 100), idle +500, iowait +200 -> 300/1000
        self.set_next(stat_delta=(200, 0, 100, 500, 200, 0, 0, 0))
        self.run_script(samples=2)
        self.assertEqual(float(self.last_row()["cpu_util_pct"]), 30.0)

    def test_cpu_util_steal_counts_as_busy(self):
        self.set_next(stat_delta=(0, 0, 0, 700, 0, 0, 0, 300))
        self.run_script(samples=2)
        self.assertEqual(float(self.last_row()["cpu_util_pct"]), 30.0)

    def test_cpu_util_nice_irq_softirq_count_as_busy(self):
        self.set_next(stat_delta=(0, 100, 0, 600, 0, 150, 150, 0))
        self.run_script(samples=2)
        self.assertEqual(float(self.last_row()["cpu_util_pct"]), 40.0)

    def test_energy_delta_gives_plausible_watts(self):
        self.set_next(energy=6000000)  # +1 J over >= 0.1 s
        self.run_script(samples=2)
        w = float(self.last_row()["cpu_pkg_w"])
        self.assertGreater(w, 0.3)
        self.assertLessEqual(w, 10.0)

    def test_energy_wrap_matches_nonwrapped_run(self):
        self.set_next(energy=6000000)
        self.run_script(samples=2)
        plain = float(self.last_row()["cpu_pkg_w"])

        self.out.unlink()
        self.energy.write_text(f"{MAX_RANGE - 500000}\n")
        self.set_next(energy=500000)  # effective delta 1,000,000 after wrap
        self.run_script(samples=2)
        wrapped = float(self.last_row()["cpu_pkg_w"])

        self.assertGreater(wrapped, 0)
        self.assertLessEqual(wrapped, 10.0)
        self.assertLess(abs(wrapped - plain) / plain, 3.0)
        self.assertGreater(wrapped, plain / 4)
        self.assertLess(wrapped, plain * 4)

    def test_mem_load_mhz_values(self):
        self.run_script(samples=1)
        row = self.last_row()
        self.assertEqual(row["mem_used_mb"], "12469")  # 12768000 / 1024 = 12468.75
        self.assertEqual(row["load1"], "0.69")
        self.assertEqual(row["cpu_mhz_avg"], "3334")  # mean 3333.67

    def test_sensor_values_rounded_to_one_decimal(self):
        self.run_script(samples=1)
        row = self.last_row()
        self.assertEqual(float(row["tctl_c"]), 45.2)
        self.assertEqual(float(row["tccd1_c"]), 51.0)
        self.assertEqual(float(row["nvme_c"]), 38.0)
        self.assertEqual(float(row["fan1_rpm"]), 1234.6)
        self.assertEqual(float(row["fan5_rpm"]), 800.0)
        self.assertEqual(float(row["fan6_rpm"]), 650.0)

    def test_missing_sensor_values_are_empty_not_null(self):
        (self.fake / "sensors.json").write_text(
            '{"k10temp-pci-00c3": {"Tctl": {"temp1_input": 45.16}},'
            ' "nct6687-isa-0a20": {"fan1": {"fan1_input": 900.0}}}'
        )
        self.run_script(samples=1)
        row = self.last_row()
        self.assertEqual(float(row["tctl_c"]), 45.2)
        self.assertEqual(float(row["fan1_rpm"]), 900.0)
        for col in ("tccd1_c", "nvme_c", "fan5_rpm", "fan6_rpm"):
            self.assertEqual(row[col], "", col)
        self.assertNotIn("null", self.out.read_text())

    def test_gpu_values_spaces_removed(self):
        self.run_script(samples=1)
        row = self.last_row()
        self.assertEqual(row["gpu_util_pct"], "12")
        self.assertEqual(row["gpu_temp_c"], "55")
        self.assertEqual(row["gpu_w"], "80.25")
        self.assertEqual(row["gpu_mem_mb"], "2048")

    def test_nvidia_smi_failure_gives_four_empty_gpu_fields(self):
        (self.fake / "gpu_fail").write_text("")
        r = self.run_script(samples=2)
        self.assertEqual(r.returncode, 0, r.stderr)
        row = self.last_row()
        for col in ("gpu_util_pct", "gpu_temp_c", "gpu_w", "gpu_mem_mb"):
            self.assertEqual(row[col], "", col)
        self.assertEqual(row["load1"], "0.69")
        self.assertEqual(row["mem_used_mb"], "12469")
        self.assertEqual(float(row["tctl_c"]), 45.2)
        self.assertEqual(float(row["fan1_rpm"]), 1234.6)

    def test_nvidia_smi_wrong_field_count_gives_empty_gpu_fields(self):
        (self.fake / "gpu.txt").write_text("12, 55, 80.25\n")
        self.run_script(samples=1)
        row = self.last_row()
        for col in ("gpu_util_pct", "gpu_temp_c", "gpu_w", "gpu_mem_mb"):
            self.assertEqual(row[col], "", col)


if __name__ == "__main__":
    unittest.main()
