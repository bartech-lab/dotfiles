#!/usr/bin/env python3
"""Write the tracked WebCatalog settings into each signed-in user's settings.json.

    webcatalog-settings.py [--dry-run] [--webcatalog-dir DIR] [--config-dir DIR]

config/webcatalog/global.json holds the keys of WebCatalog's own settings
(users/*/settings.json); config/webcatalog/<slug>.json holds the keys of one
installed web app (photon/<slug>/users/*/settings.json, "This app" in its Settings).
Each key is set under "settings"; other keys stay. A user folder appears after the
first sign-in, and an app folder after the app's first start; until then it is skipped.
The apps watch these files, so a running app picks the change up.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))


def main(argv):
    dry_run = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    opts = {"--webcatalog-dir": os.path.expanduser("~/Library/Application Support/WebCatalog"),
            "--config-dir": os.path.join(HERE, "..", "config", "webcatalog")}
    for flag in opts:
        if flag in args:
            i = args.index(flag)
            opts[flag] = args[i + 1]
            del args[i:i + 2]
    if args:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    base, config = opts["--webcatalog-dir"], opts["--config-dir"]
    for name in sorted(os.listdir(config)):
        if not name.endswith(".json"):
            continue
        slug = name[:-len(".json")]
        with open(os.path.join(config, name)) as f:
            tracked = json.load(f)
        where = base if slug == "global" else os.path.join(base, "photon", slug)
        files = sorted(glob.glob(os.path.join(where, "users", "*", "settings.json")))
        if not files:
            print(f"  skip WebCatalog {slug}: not installed or not signed in yet; start it once, then rerun")
            continue
        for path in files:
            with open(path) as f:
                data = json.load(f)
            current = data.setdefault("settings", {})
            changed = [k for k, v in tracked.items() if current.get(k) != v]
            if not changed:
                continue
            if dry_run:
                print(f"  → Would set in WebCatalog {slug}: {', '.join(changed)}")
                continue
            current.update(tracked)
            with open(path, "w") as f:
                json.dump(data, f)
            print(f"✓ WebCatalog {slug}: {len(changed)} setting(s) set")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
