#!/usr/bin/env python3
"""Apply the Chrome recommended policies on macOS.

    chrome-policies-macos.py [--dry-run] [POLICY_JSON]

Linux installs linux/etc/opt/chrome/policies/recommended/plain.json as a recommended
policy file. On macOS, Chrome reads every non-forced value in the com.google.Chrome
user defaults as a recommended policy (components/policy/core/common/policy_loader_mac.mm),
so the same JSON is written there with `defaults write`, one key at a time.
Recommended means a default the user can still change in Chrome's settings.

macOS Chrome ignores a few policies outside MDM ("This policy is blocked" in
chrome://policy, checked on Chrome 158). They are not written; the script names
them so they can be set once in Chrome's settings.
"""
import json
import os
import subprocess
import sys

DOMAIN = "com.google.Chrome"
# Policy -> what to set by hand in Chrome's settings instead.
BLOCKED_ON_MACOS = {
    "DefaultSearchProviderEnabled": "Search engine: Brave",
    "MetricsReportingEnabled": "Privacy: usage statistics and crash reports off",
    "RestoreOnStartup": "On startup: Continue where you left off",
}
# Policies Chrome has only on Windows and Linux; chrome://policy on macOS does not list them.
NOT_ON_MACOS = {"BackgroundModeEnabled", "SpellcheckLanguage"}
DEFAULT_JSON = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..",
                            "linux", "etc", "opt", "chrome", "policies", "recommended", "plain.json")


def defaults_args(key, value):
    if isinstance(value, bool):
        return [key, "-bool", "true" if value else "false"]
    if isinstance(value, int):
        return [key, "-int", str(value)]
    if isinstance(value, str):
        return [key, "-string", value]
    if isinstance(value, list) and all(isinstance(v, str) for v in value):
        return [key, "-array", *value]
    raise ValueError(f"{key}: unsupported policy value {value!r}")


def main(argv):
    dry_run = "--dry-run" in argv
    paths = [a for a in argv if a != "--dry-run"]
    with open(paths[0] if paths else DEFAULT_JSON) as f:
        policies = json.load(f)
    # The other DefaultSearchProvider* policies apply only together with DefaultSearchProviderEnabled.
    skipped = [k for k in policies if k in BLOCKED_ON_MACOS or k in NOT_ON_MACOS or k.startswith("DefaultSearchProvider")]
    commands = [["defaults", "write", DOMAIN, *defaults_args(k, v)] for k, v in policies.items() if k not in skipped]
    for cmd in commands:
        if dry_run:
            print("  → Would run: " + " ".join(cmd))
        else:
            subprocess.run(cmd, check=True)
    if not dry_run:
        print(f"✓ Chrome recommended policies: {len(commands)} set in {DOMAIN}")
    hints = [BLOCKED_ON_MACOS[k] for k in BLOCKED_ON_MACOS if k in skipped]
    if hints:
        print("  Set once in Chrome's settings (macOS blocks these policies outside MDM): " + "; ".join(hints))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
