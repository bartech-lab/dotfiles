#!/usr/bin/env python3
"""Keep the settings of macOS apps in dotfiles.

    macos-app-settings.py apply [--dry-run]     # write every tracked file into its app's defaults
    macos-app-settings.py export DOMAIN         # save an app's current settings to config/macos-apps

config/macos-apps/<domain>.plist holds the keys to set for one app (its defaults
domain, for example eu.exelban.Stats). apply merges them in key by key; other keys
stay. A sandboxed app keeps its defaults in its container, which exists only after
the app's first start, so such an app is skipped until then.

export drops keys that hold identities, tokens, timestamps or window positions,
and prints the kept key names: read them before committing, the repo is public.
"""
import os
import plistlib
import re
import subprocess
import sys

CONFIG = os.environ.get("MACOS_APP_SETTINGS_DIR") or os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "..", "config", "macos-apps")
# Key names never worth tracking: identities and secrets, timestamps, window and panel geometry, update checks.
VOLATILE = re.compile(r"(token|secret|password|passwd|credential|license|serial|email|account|uuid|_id$|^id$|"
                      r"remote|device|_ts$|date|time|last|recent|history|count|window|frame|NSSplitView|"
                      r"NSToolbar|NSNavPanel|NSTableView|NSOutlineView|^SU|update|version|migrat|onboard|"
                      r"security|private|cert|key$)", re.I)


def domain_target(domain):
    """The name `defaults` takes: the domain, or the plist path inside the app's container."""
    container = os.path.expanduser(f"~/Library/Containers/{domain}")
    if os.path.isdir(container):
        return os.path.join(container, "Data", "Library", "Preferences", domain)
    return domain


def sandboxed(domain):
    app = subprocess.run(["mdfind", f"kMDItemCFBundleIdentifier == '{domain}'"], capture_output=True, text=True).stdout
    for path in app.splitlines():
        ent = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", path], capture_output=True)
        if b"com.apple.security.app-sandbox" in ent.stdout:
            return True
    return False


def read_domain(target):
    r = subprocess.run(["defaults", "export", target, "-"], capture_output=True)
    return plistlib.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {}


def apply(dry_run):
    rc = 0
    for name in sorted(os.listdir(CONFIG)):
        if not name.endswith(".plist"):
            continue
        domain = name[:-len(".plist")]
        with open(os.path.join(CONFIG, name), "rb") as f:
            tracked = plistlib.load(f)
        target = domain_target(domain)
        if target == domain and sandboxed(domain):
            print(f"  skip {domain}: start the app once, then rerun macos-app-settings apply")
            continue
        current = read_domain(target)
        changed = [k for k, v in tracked.items() if current.get(k) != v]
        if not changed:
            continue
        if dry_run:
            print(f"  → Would set in {domain}: {', '.join(changed)}")
            continue
        current.update(tracked)
        r = subprocess.run(["defaults", "import", target, "-"], input=plistlib.dumps(current))
        if r.returncode:
            print(f"❌ {domain}: defaults import failed", file=sys.stderr)
            rc = 1
        else:
            print(f"✓ {domain}: {len(changed)} setting(s) set (restart the app if it is open)")
    return rc


def export(domain):
    current = read_domain(domain_target(domain))
    if not current:
        print(f"❌ {domain}: no settings found", file=sys.stderr)
        return 1
    kept = {k: v for k, v in current.items() if not VOLATILE.search(k) and not isinstance(v, bytes)}
    os.makedirs(CONFIG, exist_ok=True)
    with open(os.path.join(CONFIG, domain + ".plist"), "wb") as f:
        plistlib.dump(kept, f, sort_keys=True)
    print(f"✓ {domain}: kept {len(kept)} of {len(current)} keys: {', '.join(sorted(kept))}")
    return 0


def main(argv):
    if argv[:1] == ["apply"]:
        return apply("--dry-run" in argv)
    if argv[:1] == ["export"] and len(argv) == 2:
        return export(argv[1])
    print("usage:\n" + "\n".join(__doc__.strip().splitlines()[2:4]), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
