"""Behavior tests for photo-dupes, built from the spec only. Run: python3 -m unittest linux/tests/test_photo_dupes.py"""

import io
import os
import random
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "photo-dupes"
SIZE = (640, 480)


def scene(seed, fine=True):
    """Low-frequency colour field + shapes (+ fine noise that only a sharp copy keeps)."""
    rng = random.Random(seed)
    w, h = SIZE
    small = Image.frombytes("RGB", (16, 12), bytes(rng.randrange(256) for _ in range(16 * 12 * 3)))
    img = small.resize(SIZE, Image.BICUBIC)
    draw = ImageDraw.Draw(img)
    for _ in range(14):
        x, y = rng.randrange(w - 60), rng.randrange(h - 60)
        r = rng.randrange(30, 120)
        draw.ellipse((x, y, x + r, y + r), fill=tuple(rng.randrange(256) for _ in range(3)), outline=(0, 0, 0))
    if fine:
        noise = Image.frombytes("L", SIZE, bytes(rng.randrange(256) for _ in range(w * h))).convert("RGB")
        img = Image.blend(img, noise, 0.15)
    return img


def shifted(img, dx=10, dy=6, margin=16):
    """Slightly cropped and shifted view of the same scene, resized back to full size."""
    w, h = img.size
    return img.crop((dx, dy, dx + w - margin, dy + h - margin)).resize(img.size, Image.BICUBIC)


def save_jpeg(path, img, taken=None, subsec="25"):
    kwargs = {}
    if taken:
        exif = Image.Exif()
        ifd = exif.get_ifd(0x8769)
        ifd[0x9003] = taken
        ifd[0x9291] = subsec
        kwargs["exif"] = exif
    img.save(path, "JPEG", quality=92, subsampling=0, **kwargs)


def snapshot(folder):
    return {
        p.name: (p.lstat().st_size, p.lstat().st_mtime_ns, p.read_bytes())
        for p in sorted(Path(folder).iterdir())
    }


class PhotoDupes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.dir = base / "photos"
        self.out = base / "out"
        self.cache = base / "cache"
        self.dir.mkdir()
        self.cache.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *args, out=True):
        env = {**os.environ, "XDG_CACHE_HOME": str(self.cache), "HOME": self.tmp.name}
        extra = ["--out", str(self.out)] if out else []
        return subprocess.run([str(SCRIPT), *extra, *args, str(self.dir)], env=env, capture_output=True, text=True)

    def groups(self, stdout):
        """Split the report into the text of each `group <n>:` block."""
        blocks, current = [], None
        for line in stdout.splitlines():
            if re.match(r"group \d+:", line):
                current = [line]
                blocks.append(current)
            elif current is not None and (line.startswith(" ") or line.startswith("\t") or line.startswith("suggest keep:")):
                current.append(line)
            else:
                current = None
        return ["\n".join(b) for b in blocks]

    def make_pair(self, taken_a="2024:05:06 07:08:09", taken_b="2024:05:06 07:08:11"):
        sharp = scene(1)
        blurred = shifted(sharp).filter(ImageFilter.GaussianBlur(3))
        # blurred copy sorts first so "first member" or "first file" cannot win by accident
        save_jpeg(self.dir / "a_blurred.jpg", blurred, taken_a)
        save_jpeg(self.dir / "b_sharp.jpg", sharp, taken_b)

    def test_exact_duplicates_are_reported_on_an_exact_line(self):
        img = scene(2)
        save_jpeg(self.dir / "orig.jpg", img, "2024:01:01 10:00:00")
        (self.dir / "copy.JPG").write_bytes((self.dir / "orig.jpg").read_bytes())
        img.save(self.dir / "p1.png")
        (self.dir / "p2.png").write_bytes((self.dir / "p1.png").read_bytes())
        save_jpeg(self.dir / "zzdiff.jpg", scene(99), "2020:03:03 03:03:03")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [l for l in result.stdout.splitlines() if l.startswith("exact:")]
        self.assertEqual(len(lines), 2, result.stdout)
        jpeg_line = next(l for l in lines if "orig.jpg" in l)
        self.assertIn("copy.JPG", jpeg_line)
        self.assertNotIn("p1.png", jpeg_line)
        png_line = next(l for l in lines if "p1.png" in l)
        self.assertIn("p2.png", png_line)
        self.assertNotIn("zzdiff", result.stdout)

    def test_near_duplicates_are_grouped_and_the_sharper_one_is_suggested(self):
        self.make_pair()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        groups = self.groups(result.stdout)
        self.assertEqual(len(groups), 1, result.stdout)
        block = groups[0]
        self.assertIn("a_blurred.jpg", block)
        self.assertIn("b_sharp.jpg", block)
        keep = [l for l in block.splitlines() if l.startswith("suggest keep:")]
        self.assertEqual(len(keep), 1)
        self.assertIn("b_sharp.jpg", keep[0])
        self.assertNotIn("a_blurred", keep[0])
        self.assertNotIn("exact:", result.stdout)

    def test_the_sharper_copy_wins_whichever_name_sorts_first(self):
        sharp = scene(1)
        save_jpeg(self.dir / "a_sharp.jpg", sharp, "2024:05:06 07:08:09")
        save_jpeg(self.dir / "b_blurred.jpg", shifted(sharp).filter(ImageFilter.GaussianBlur(3)), "2024:05:06 07:08:10")
        result = self.run_script()
        keep = [l for l in result.stdout.splitlines() if l.startswith("suggest keep:")]
        self.assertEqual(len(keep), 1, result.stdout)
        self.assertIn("a_sharp.jpg", keep[0])

    def test_different_photo_at_the_same_time_is_not_grouped(self):
        self.make_pair()
        save_jpeg(self.dir / "zzdiff.jpg", scene(77), "2024:05:06 07:08:10")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("zzdiff", result.stdout)
        self.assertEqual(len(self.groups(result.stdout)), 1)

    def test_a_lone_different_pair_produces_no_group(self):
        save_jpeg(self.dir / "one.jpg", scene(5), "2024:05:06 07:08:09")
        save_jpeg(self.dir / "two.jpg", scene(6), "2024:05:06 07:08:09")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.groups(result.stdout), [])
        self.assertNotIn("suggest keep:", result.stdout)

    def test_near_duplicates_outside_the_time_window_are_not_compared(self):
        self.make_pair(taken_a="2024:05:06 07:00:00", taken_b="2024:05:06 09:00:00")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.groups(result.stdout), [])

    def test_a_wider_window_compares_them(self):
        self.make_pair(taken_a="2024:05:06 07:00:00", taken_b="2024:05:06 09:00:00")
        result = self.run_script("--window", "86400")
        self.assertEqual(len(self.groups(result.stdout)), 1, result.stdout)

    def test_a_photo_without_capture_time_is_still_compared(self):
        sharp = scene(1)
        save_jpeg(self.dir / "a_blurred.jpg", shifted(sharp).filter(ImageFilter.GaussianBlur(3)))
        save_jpeg(self.dir / "b_sharp.jpg", sharp, "2024:05:06 07:08:09")
        result = self.run_script()
        groups = self.groups(result.stdout)
        self.assertEqual(len(groups), 1, result.stdout)
        self.assertIn("suggest keep:", groups[0])
        self.assertIn("b_sharp.jpg", groups[0].split("suggest keep:")[1])

    def test_input_folder_is_unchanged_and_out_is_honoured(self):
        self.make_pair()
        (self.dir / "twin.jpg").write_bytes((self.dir / "b_sharp.jpg").read_bytes())
        before = snapshot(self.dir)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(snapshot(self.dir), before)
        report = self.out / "report.txt"
        self.assertTrue(report.is_file())
        self.assertIn("suggest keep:", report.read_text())
        sheets = [p for p in self.out.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"}]
        self.assertTrue(sheets, "expected a contact sheet image in --out")
        self.assertEqual(list(self.cache.iterdir()), [], "default cache dir must stay unused when --out is given")

    def test_default_out_goes_to_the_xdg_cache_dir(self):
        self.make_pair()
        result = self.run_script(out=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        reports = list((self.cache / "photo-dupes").glob("*/report.txt"))
        self.assertEqual(len(reports), 1)

    def test_missing_directory_is_a_usage_error(self):
        env = {**os.environ, "XDG_CACHE_HOME": str(self.cache)}
        result = subprocess.run([str(SCRIPT), str(self.dir / "nope")], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
