#!/usr/bin/env python3
"""Write the tracked browser settings into the browser's own preference files.

    browser-prefs.py brave|chrome [--dry-run] [--user-data-dir DIR] [PREFS_JSON]

PREFS_JSON (default config/<browser>/preferences.json) maps a file inside the
browser's user data directory ("Default/Preferences", "Local State") to the values
to set there. Each value is merged in key by key; every other setting stays as it
is. Brave has no policy for most of its settings (new tab widgets, toolbar buttons,
sidebar), so they go straight into the files the browser reads at start.

"external_extensions" maps extension IDs to names. On macOS each one gets an
"External Extensions/<id>.json" file, so the browser offers to install it from the
Chrome Web Store at the next start; the user still enables it.

The browser rewrites its preference files while it runs, so they are never written
while it is open.
"""
import json
import os
import platform
import sys

CONFIG_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "config")
BROWSERS = {  # name: (macOS folder under Application Support, Linux folder under ~/.config, display name)
    "brave": ("BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser", "Brave"),
    "chrome": ("Google/Chrome", "google-chrome", "Chrome"),
}
WEB_STORE = "https://clients2.google.com/service/update2/crx"


def default_user_data_dir(browser):
    mac, linux, _ = BROWSERS[browser]
    if platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/" + mac)
    return os.path.expanduser("~/.config/" + linux)


def browser_running(user_data_dir):
    """Chromium keeps SingletonLock -> "<host>-<pid>" while the profile is open."""
    try:
        target = os.readlink(os.path.join(user_data_dir, "SingletonLock"))
    except OSError:
        return False
    host, _, pid = target.rpartition("-")
    if host != platform.node() or not pid.isdigit():
        return True  # another machine's lock, or unreadable: do not touch the files
    try:
        os.kill(int(pid), 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def merge(dst, src):
    """Set every leaf of src in dst; return the dotted names whose value changed."""
    changed = []
    for key, value in src.items():
        if isinstance(value, dict):
            if not isinstance(dst.get(key), dict):
                dst[key] = {}
            changed += [f"{key}.{name}" for name in merge(dst[key], value)]
        elif dst.get(key) != value:
            dst[key] = value
            changed.append(key)
    return changed


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".browser-prefs-tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(tmp, path)


def main(argv):
    dry_run = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if not args or args[0] not in BROWSERS:
        print("usage: browser-prefs.py brave|chrome [--dry-run] [--user-data-dir DIR] [PREFS_JSON]", file=sys.stderr)
        return 2
    browser = args.pop(0)
    label = BROWSERS[browser][2]
    user_data_dir = default_user_data_dir(browser)
    if "--user-data-dir" in args:
        i = args.index("--user-data-dir")
        user_data_dir = args[i + 1]
        del args[i:i + 2]
    with open(args[0] if args else os.path.join(CONFIG_DIR, browser, "preferences.json")) as f:
        tracked = json.load(f)
    extensions = tracked.pop("external_extensions", {})

    # Extension files are read only at start, so they are safe to add while the browser runs.
    if tracked and browser_running(user_data_dir):
        print(f"⚠️  {label} is open; quit it and rerun: python3 ~/dotfiles/scripts/browser-prefs.py {browser}",
              file=sys.stderr)
        return 1

    for name, values in tracked.items():
        path = os.path.join(user_data_dir, name)
        current = {}
        if os.path.exists(path):
            with open(path) as f:
                current = json.load(f)
        changed = merge(current, values)
        if dry_run:
            for key in changed:
                print(f"  → Would set in {name}: {key}")
        elif changed:
            write_json(path, current)
            print(f"✓ {label} {name}: {len(changed)} setting(s) set")

    if platform.system() == "Darwin":
        for ext_id, ext_name in extensions.items():
            path = os.path.join(user_data_dir, "External Extensions", ext_id + ".json")
            if os.path.exists(path):
                continue
            if dry_run:
                print(f"  → Would offer extension: {ext_name}")
            else:
                write_json(path, {"external_update_url": WEB_STORE})
                print(f"✓ {label} will offer the extension {ext_name} at next start")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
