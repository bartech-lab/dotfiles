#!/usr/bin/env python3
"""Write the tracked Spotify settings into each signed-in user's prefs file.

    spotify-prefs.py [--dry-run] [--spotify-dir DIR] [TRACKED]

TRACKED (default config/spotify/user-prefs) holds key=value lines. Each key is set in
every Users/*-user/prefs under the Spotify folder; other keys stay. Spotify rewrites the
file when it quits, so nothing is written while it runs. A user folder appears after
the first sign-in, so on a new machine sign in once, quit, and rerun.
"""
import glob
import os
import platform
import subprocess
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "config", "spotify", "user-prefs")


def spotify_dir():
    if platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Spotify")
    return os.path.expanduser("~/.config/spotify")


def spotify_running():
    name = "Spotify" if platform.system() == "Darwin" else "spotify"
    return subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0


def read_pairs(path):
    pairs = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                pairs[key] = value
    return pairs


def main(argv):
    dry_run = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    base = spotify_dir()
    if "--spotify-dir" in args:
        i = args.index("--spotify-dir")
        base = args[i + 1]
        del args[i:i + 2]
    tracked = read_pairs(args[0] if args else DEFAULT)
    files = sorted(glob.glob(os.path.join(base, "Users", "*-user", "prefs")))
    if not files:
        print("  skip Spotify settings: no signed-in user yet; sign in once, quit Spotify, rerun")
        return 0
    if not dry_run and spotify_running():
        print("⚠️  Spotify is open; quit it and rerun: python3 ~/dotfiles/scripts/spotify-prefs.py", file=sys.stderr)
        return 1
    for path in files:
        with open(path) as f:
            lines = f.read().splitlines()
        current = {l.split("=", 1)[0]: l.split("=", 1)[1] for l in lines if "=" in l}
        changed = [k for k, v in tracked.items() if current.get(k) != v]
        if not changed:
            continue
        if dry_run:
            print(f"  → Would set in Spotify prefs: {', '.join(changed)}")
            continue
        kept = [l for l in lines if l.split("=", 1)[0] not in tracked]
        with open(path, "w") as f:
            f.write("\n".join(kept + [f"{k}={v}" for k, v in tracked.items()]) + "\n")
        print(f"✓ Spotify: {len(changed)} setting(s) set")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
