"""Behavior tests for photo-shrink, built from the spec only. Run: python3 -m unittest linux/tests/test_photo_shrink.py"""

import io
import os
import random
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, JpegImagePlugin

SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "photo-shrink"
OLD_MTIME = 1_500_000_000  # whole seconds, so float and ns round-trips agree
EXIF_TIME = "2024:05:06 07:08:09"
HDR_PAYLOAD = b"urn:iso:std:iso:ts:21496:-1\x00" + b"\x01\x02\x03\x04"


def textured(size=(640, 480), seed=1):
    """Low-frequency colour field + shapes + fine noise, so SSIM and file size are meaningful."""
    rng = random.Random(seed)
    w, h = size
    small = Image.frombytes("RGB", (16, 12), bytes(rng.randrange(256) for _ in range(16 * 12 * 3)))
    img = small.resize(size, Image.BICUBIC)
    draw = ImageDraw.Draw(img)
    for _ in range(12):
        x, y = rng.randrange(w), rng.randrange(h)
        r = rng.randrange(15, 80)
        colour = tuple(rng.randrange(256) for _ in range(3))
        draw.ellipse((x, y, x + r, y + r), fill=colour, outline=(0, 0, 0))
    noise = Image.frombytes("L", size, bytes(rng.randrange(256) for _ in range(w * h))).convert("RGB")
    return Image.blend(img, noise, 0.15)


def jpeg_bytes(quality, size=(640, 480), seed=1, exif_time=None, subsampling=0):
    buf = io.BytesIO()
    kwargs = {}
    if exif_time:
        exif = Image.Exif()
        exif.get_ifd(0x8769)[0x9003] = exif_time
        kwargs["exif"] = exif
    textured(size, seed).save(buf, "JPEG", quality=quality, subsampling=subsampling, **kwargs)
    return buf.getvalue()


def mpo_bytes():
    buf = io.BytesIO()
    first = textured((640, 480), 3)
    first.save(buf, format="MPO", save_all=True, append_images=[textured((160, 120), 4)])
    data = buf.getvalue()
    with Image.open(io.BytesIO(data)) as im:
        assert getattr(im, "n_frames", 1) == 2, "fixture must be a 2-frame MPO"
    return data


def with_hdr_marker(data):
    assert data[:2] == b"\xff\xd8"
    return data[:2] + b"\xff\xe2" + struct.pack(">H", len(HDR_PAYLOAD) + 2) + HDR_PAYLOAD + data[2:]


def tiff_with_strip(jpeg, order="II", strip_len=None, with_strip=True, size=(640, 480)):
    """Minimal DNG-like TIFF: IFD0 right after the header, one strip right after the IFD."""
    e = "<" if order == "II" else ">"
    short = lambda v: struct.pack(e + "H", v) + b"\0\0"
    long_ = lambda v: struct.pack(e + "I", v)
    entries = [
        (254, 4, long_(0)),
        (256, 4, long_(size[0])),
        (257, 4, long_(size[1])),
        (259, 3, short(7 if with_strip else 1)),
    ]
    count = 4 + (2 if with_strip else 0)
    data_off = 8 + 2 + count * 12 + 4
    if with_strip:
        entries.append((273, 4, long_(data_off)))
        entries.append((279, 4, long_(len(jpeg) if strip_len is None else strip_len)))
    out = (b"II*\0" if order == "II" else b"MM\0*") + struct.pack(e + "I", 8)
    out += struct.pack(e + "H", len(entries))
    for tag, typ, val in entries:
        out += struct.pack(e + "HHI", tag, typ, 1) + val
    out += struct.pack(e + "I", 0)
    assert len(out) == data_off
    return out + (jpeg if with_strip else b"\x00" * 64)


def snapshot(folder):
    snap = {}
    for p in sorted(Path(folder).iterdir()):
        st = p.lstat()
        snap[p.name] = (st.st_size, st.st_mtime_ns, p.read_bytes() if p.is_file() else None)
    return snap


class PhotoShrinkCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.dir = base / "photos"
        self.trash = base / "trash"
        self.dir.mkdir()
        self.trash.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, data, mtime=OLD_MTIME):
        p = self.dir / name
        p.write_bytes(data)
        os.utime(p, (mtime, mtime))
        return p

    def run_script(self, *args):
        env = {**os.environ, "PHOTO_SHRINK_TRASH_DIR": str(self.trash)}
        return subprocess.run([str(SCRIPT), *args], env=env, capture_output=True, text=True)

    def apply(self, *extra):
        return self.run_script("--apply", *extra, str(self.dir))

    def trashed(self):
        return sorted(p.name for p in self.trash.iterdir())


class DryRun(PhotoShrinkCase):
    def test_dry_run_changes_nothing(self):
        self.put("a.DNG", tiff_with_strip(jpeg_bytes(90)))
        self.put("b.jpg", jpeg_bytes(100, seed=2))
        self.put("c.png", (lambda b: (textured((200, 150), 5).save(b, "PNG"), b.getvalue())[1])(io.BytesIO()))
        self.put("d.jpg", with_hdr_marker(jpeg_bytes(100, seed=6)))
        self.put("clip.mov", b"\x00\x00\x00\x14ftypqt  ")
        before = snapshot(self.dir)
        result = self.run_script(str(self.dir))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])
        self.assertIn("EXTRACT a.DNG -> a.jpg", result.stdout)
        self.assertIn("RECOMPRESS b.jpg", result.stdout)
        self.assertIn("CONVERT c.png -> c.jpg", result.stdout)
        self.assertTrue(result.stdout.strip().splitlines()[-1].startswith("done:"))


class DngExtract(PhotoShrinkCase):
    def check_extract(self, order):
        jpeg = jpeg_bytes(90, seed=7, exif_time=EXIF_TIME)
        dng = self.put("IMG_1.DNG", tiff_with_strip(jpeg, order))
        mtime_ns = dng.stat().st_mtime_ns
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("EXTRACT IMG_1.DNG -> IMG_1.jpg", result.stdout)
        out = self.dir / "IMG_1.jpg"
        self.assertEqual(out.read_bytes(), jpeg)
        self.assertEqual(out.stat().st_mtime_ns, mtime_ns)
        self.assertFalse(dng.exists())
        self.assertEqual(self.trashed(), ["IMG_1.DNG"])
        self.assertTrue(result.stdout.strip().splitlines()[-1].startswith("done:"))

    def test_little_endian_dng_extracts_bit_exact_jpeg(self):
        self.check_extract("II")

    def test_big_endian_dng_extracts_bit_exact_jpeg(self):
        self.check_extract("MM")

    def test_embedded_mpo_keeps_both_frames(self):
        mpo = mpo_bytes()
        self.put("IMG_2.dng", tiff_with_strip(mpo))
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = (self.dir / "IMG_2.jpg").read_bytes()
        self.assertEqual(data, mpo)
        with Image.open(io.BytesIO(data)) as im:
            self.assertEqual(im.n_frames, 2)

    def test_dng_that_is_really_a_jpeg_is_renamed_untouched(self):
        jpeg = jpeg_bytes(95, seed=8)
        dng = self.put("IMG_3.DNG", jpeg)
        mtime_ns = dng.stat().st_mtime_ns
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RENAME IMG_3.DNG -> IMG_3.jpg", result.stdout)
        out = self.dir / "IMG_3.jpg"
        self.assertEqual(out.read_bytes(), jpeg)
        self.assertEqual(out.stat().st_mtime_ns, mtime_ns)
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), ["IMG_3.jpg"])
        self.assertEqual(self.trashed(), [])

    def assert_dng_skipped(self, name, data):
        self.put(name, data)
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"SKIP {name}: no embedded JPEG", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])

    def test_dng_without_a_strip_is_skipped(self):
        self.assert_dng_skipped("raw.dng", tiff_with_strip(b"", with_strip=False))

    def test_dng_whose_strip_runs_past_end_of_file_is_skipped(self):
        jpeg = jpeg_bytes(90, seed=9)
        self.assert_dng_skipped("long.dng", tiff_with_strip(jpeg, strip_len=len(jpeg) + 1000))

    def test_dng_strip_that_is_not_a_complete_jpeg_is_skipped(self):
        jpeg = jpeg_bytes(90, seed=9)
        self.assert_dng_skipped("cut.dng", tiff_with_strip(jpeg[:-2] + b"\x00\x00"))

    def test_extraction_that_does_not_decode_fails_verify_and_keeps_the_dng(self):
        bad = b"\xff\xd8" + b"not really a jpeg" * 20 + b"\xff\xd9"
        self.put("bad.dng", tiff_with_strip(bad))
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 1)
        self.assertIn("SKIP bad.dng: verify failed", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])

    def test_existing_jpeg_with_other_letter_case_blocks_extraction(self):
        self.put("IMG_4.Jpeg", jpeg_bytes(90, seed=10))
        self.put("IMG_4.dng", tiff_with_strip(jpeg_bytes(90, seed=11)))
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SKIP IMG_4.dng: target exists", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])


class Recompress(PhotoShrinkCase):
    def test_q100_jpeg_is_recompressed_smaller_with_metadata_kept(self):
        original = jpeg_bytes(100, seed=12, exif_time=EXIF_TIME)
        path = self.put("IMG_5.jpg", original)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RECOMPRESS IMG_5.jpg", result.stdout)
        new = path.read_bytes()
        self.assertLess(len(new), len(original))
        self.assertEqual(path.stat().st_mtime_ns, OLD_MTIME * 10**9)
        with Image.open(path) as im, Image.open(io.BytesIO(original)) as old:
            self.assertEqual(im.size, old.size)
            self.assertEqual(im.getexif().get_ifd(0x8769).get(0x9003), EXIF_TIME)
            self.assertEqual(JpegImagePlugin.get_sampling(im), 0)
        self.assertEqual(self.trashed(), ["IMG_5.jpg"])
        self.assertEqual((self.trash / "IMG_5.jpg").read_bytes(), original)
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), ["IMG_5.jpg"])

    def test_q100_jpeg_with_hdr_marker_is_skipped_untouched(self):
        self.put("hdr.jpg", with_hdr_marker(jpeg_bytes(100, seed=13)))
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SKIP hdr.jpg: HDR", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])

    def test_q85_jpeg_is_left_alone_silently(self):
        self.put("IMG_6.JPG", jpeg_bytes(85, seed=14, subsampling=2))
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("IMG_6", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])


class Convert(PhotoShrinkCase):
    @staticmethod
    def png(mode="RGB", alpha=255):
        img = textured((320, 240), 15).convert(mode)
        if mode == "RGBA":
            img.putalpha(alpha if isinstance(alpha, Image.Image) else Image.new("L", img.size, alpha))
        buf = io.BytesIO()
        img.save(buf, "PNG")
        return buf.getvalue()

    def check_converted(self, name, data):
        self.put(name, data)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"CONVERT {name} -> IMG_7.jpg", result.stdout)
        out = self.dir / "IMG_7.jpg"
        with Image.open(out) as im:
            self.assertEqual(im.format, "JPEG")
            self.assertEqual(im.size, (320, 240))
            self.assertEqual(JpegImagePlugin.get_sampling(im), 0)
        self.assertEqual(out.stat().st_mtime_ns, OLD_MTIME * 10**9)
        self.assertEqual(self.trashed(), [name])
        self.assertFalse((self.dir / name).exists())

    def test_opaque_png_is_converted_and_original_trashed(self):
        self.check_converted("IMG_7.png", self.png())

    def test_rgba_png_with_full_alpha_is_converted(self):
        self.check_converted("IMG_7.PNG", self.png("RGBA", 255))

    def test_png_with_one_transparent_pixel_is_skipped(self):
        alpha = Image.new("L", (320, 240), 255)
        alpha.putpixel((5, 5), 254)
        self.put("alpha.png", self.png("RGBA", alpha))
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SKIP alpha.png: transparency", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])

    def test_existing_target_in_other_case_is_never_overwritten(self):
        self.put("IMG_1.JPG", jpeg_bytes(85, seed=16, subsampling=2))
        self.put("IMG_1.PNG", self.png())
        before = snapshot(self.dir)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SKIP IMG_1.PNG: target exists", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual(self.trashed(), [])


class Misc(PhotoShrinkCase):
    def test_unrelated_files_are_ignored_silently(self):
        self.put("clip.mov", b"\x00\x00\x00\x14ftypqt  " + os.urandom(64))
        self.put("notes.txt", b"hello")
        (self.dir / "sub").mkdir()
        self.put("sub/inner.jpg", jpeg_bytes(100, seed=17))
        before = snapshot(self.dir)
        inner = (self.dir / "sub" / "inner.jpg").read_bytes()
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("clip.mov", result.stdout)
        self.assertNotIn("notes.txt", result.stdout)
        self.assertEqual(snapshot(self.dir), before)
        self.assertEqual((self.dir / "sub" / "inner.jpg").read_bytes(), inner)
        self.assertEqual(self.trashed(), [])

    def test_missing_directory_is_a_usage_error(self):
        result = self.run_script("--apply", str(self.dir / "nope"))
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stderr.strip())

    def test_regular_file_instead_of_directory_is_a_usage_error(self):
        f = self.put("a.txt", b"x")
        self.assertEqual(self.run_script(str(f)).returncode, 2)

    def test_no_directory_is_a_usage_error(self):
        self.assertEqual(self.run_script("--apply").returncode, 2)

    def test_help_exits_zero(self):
        result = self.run_script("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("photo-shrink", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
