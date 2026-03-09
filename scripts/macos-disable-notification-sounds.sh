#!/usr/bin/env zsh

set -euo pipefail

typeset -a excludes=()
dry_run=false
verbose=false
list_only=false

usage() {
    cat <<'EOF'
Usage: macos-disable-notification-sounds.sh [options]

Disable macOS notification sounds for every app listed in System Settings.

Options:
  --dry-run            Show what would change without modifying settings
  --verbose            Print per-app progress details
  --list               List discovered notification entries and exit
  --exclude <app>      Skip an exact app name shown in Notifications
  --help, -h           Show this help message

Examples:
  macos-disable-notification-sounds.sh
  macos-disable-notification-sounds.sh --dry-run --verbose
  macos-disable-notification-sounds.sh --exclude "Microsoft Defender"
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --dry-run)
            dry_run=true
            ;;
        --verbose)
            verbose=true
            ;;
        --list)
            list_only=true
            ;;
        --exclude)
            shift
            if (( $# == 0 )); then
                print -u2 "Missing value for --exclude"
                usage
                exit 1
            fi
            excludes+=("$1")
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

exclude_file="$tmp_dir/excludes.txt"
printf '%s\n' "${excludes[@]}" > "$exclude_file"

swift_file="$tmp_dir/notification_sounds.swift"
cat > "$swift_file" <<'SWIFT'
import Foundation
import AppKit
import ApplicationServices

struct Counts {
    var changed = 0
    var alreadyOff = 0
    var skippedExcluded = 0
    var skippedLocked = 0
    var failed = 0
    var wouldChange = 0
}

struct Entry {
    let label: String
    let index: Int
}

let env = ProcessInfo.processInfo.environment
let dryRun = env["DOTFILES_NOTIFICATION_DRY_RUN"] == "1"
let verbose = env["DOTFILES_NOTIFICATION_VERBOSE"] == "1"
let listOnly = env["DOTFILES_NOTIFICATION_LIST_ONLY"] == "1"
let excludePath = env["DOTFILES_NOTIFICATION_EXCLUDE_FILE"] ?? ""

func loadExcludedNames(from path: String) -> Set<String> {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
        return []
    }

    let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    return Set(content
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { normalizeName(String($0)) })
}

func normalizeName(_ string: String) -> String {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let filteredScalars = trimmed.unicodeScalars.filter { scalar in
        switch scalar.properties.generalCategory {
        case .format, .control, .nonspacingMark, .enclosingMark:
            return false
        default:
            return true
        }
    }
    let collapsed = String(String.UnicodeScalarView(filteredScalars))
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return collapsed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

let excludedNames = loadExcludedNames(from: excludePath)

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return error == .success ? (value as AnyObject?) : nil
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func descendants(of element: AXUIElement) -> [AXUIElement] {
    let directChildren = children(of: element)
    return directChildren + directChildren.flatMap(descendants)
}

func stringValue(_ value: AnyObject?) -> String {
    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return ""
}

func role(of element: AXUIElement) -> String {
    stringValue(attr(element, kAXRoleAttribute))
}

func title(of element: AXUIElement) -> String {
    stringValue(attr(element, kAXTitleAttribute))
}

func detail(of element: AXUIElement) -> String {
    stringValue(attr(element, kAXDescriptionAttribute))
}

func value(of element: AXUIElement) -> String {
    stringValue(attr(element, kAXValueAttribute))
}

func enabled(of element: AXUIElement) -> Bool {
    stringValue(attr(element, kAXEnabledAttribute)) != "0"
}

@discardableResult
func press(_ element: AXUIElement) -> AXError {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
}

func launchNotificationsPane() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
    try? process.run()
    process.waitUntilExit()
    Thread.sleep(forTimeInterval: 2.0)
}

func systemSettingsWindow() -> AXUIElement? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
        return nil
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let windows = attr(appElement, kAXWindowsAttribute) as? [AXUIElement], let window = windows.first else {
        return nil
    }
    return window
}

func isOverview(_ window: AXUIElement) -> Bool {
    title(of: window) == "Notifications"
}

func backButton(in window: AXUIElement) -> AXUIElement? {
    descendants(of: window).first { detail(of: $0) == "Back" }
}

func ensureOverview() throws {
    for _ in 0..<5 {
        guard let window = systemSettingsWindow() else {
            throw NSError(domain: "NotificationSounds", code: 1, userInfo: [NSLocalizedDescriptionKey: "System Settings window is not available"])
        }
        if isOverview(window) {
            return
        }
        guard let back = backButton(in: window) else {
            throw NSError(domain: "NotificationSounds", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not navigate back to Notifications overview"])
        }
        _ = press(back)
        Thread.sleep(forTimeInterval: 1.0)
    }
    throw NSError(domain: "NotificationSounds", code: 3, userInfo: [NSLocalizedDescriptionKey: "Timed out returning to Notifications overview"])
}

func overviewEntries(in window: AXUIElement) -> [Entry] {
    let buttons = descendants(of: window).filter { role(of: $0) == "AXButton" }
    let ignored = Set(["Search", "Help", "Back", "Forward"])
    let labels = buttons
        .map { detail(of: $0) }
        .filter { !$0.isEmpty && !ignored.contains($0) }

    return labels.enumerated().map { Entry(label: $0.element, index: $0.offset) }
}

func pressOverviewEntry(at index: Int) throws -> String {
    guard let window = systemSettingsWindow() else {
        throw NSError(domain: "NotificationSounds", code: 4, userInfo: [NSLocalizedDescriptionKey: "System Settings window is not available"])
    }
    let buttons = descendants(of: window).filter { role(of: $0) == "AXButton" }
    let ignored = Set(["Search", "Help", "Back", "Forward"])
    let appButtons = buttons.filter { label in
        let description = detail(of: label)
        return !description.isEmpty && !ignored.contains(description)
    }

    guard index < appButtons.count else {
        throw NSError(domain: "NotificationSounds", code: 5, userInfo: [NSLocalizedDescriptionKey: "Notification entry index \(index) is out of range"])
    }

    let button = appButtons[index]
    let label = detail(of: button)
    _ = press(button)
    Thread.sleep(forTimeInterval: 1.0)
    return label
}

func detailScrollArea(in window: AXUIElement) -> AXUIElement? {
    let scrollAreas = descendants(of: window).filter { role(of: $0) == "AXScrollArea" }
    return scrollAreas.count >= 2 ? scrollAreas[1] : nil
}

func soundCheckbox(in detailArea: AXUIElement) -> AXUIElement? {
    for group in descendants(of: detailArea).filter({ role(of: $0) == "AXGroup" }) {
        let staticTexts = descendants(of: group)
            .filter { role(of: $0) == "AXStaticText" }
            .map { value(of: $0) }

        if staticTexts.contains("Play sound for notification") {
            return descendants(of: group).filter { role(of: $0) == "AXCheckBox" }.last
        }
    }
    return nil
}

func baseAppName(from label: String) -> String {
    label.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? label
}

func log(_ message: String) {
    if verbose {
        print(message)
    }
}

func process(entries: [Entry]) throws -> Counts {
    var counts = Counts()

    for entry in entries {
        let appName = baseAppName(from: entry.label)
        let normalizedName = normalizeName(appName)

        if excludedNames.contains(normalizedName) {
            counts.skippedExcluded += 1
            log("skip excluded: \(appName)")
            continue
        }

        if !entry.label.contains("Sounds") {
            counts.alreadyOff += 1
            log("already off: \(appName)")
            continue
        }

        try ensureOverview()
        let currentLabel = try pressOverviewEntry(at: entry.index)

        guard let window = systemSettingsWindow(), let detailArea = detailScrollArea(in: window) else {
            counts.failed += 1
            print("failed: \(appName) (detail view not available)")
            continue
        }

        guard let checkbox = soundCheckbox(in: detailArea) else {
            counts.failed += 1
            print("failed: \(appName) (sound toggle not found)")
            try? ensureOverview()
            continue
        }

        let before = value(of: checkbox)

        if !enabled(of: checkbox) {
            counts.skippedLocked += 1
            print("skipped locked: \(appName)")
            try? ensureOverview()
            continue
        }

        if before == "0" {
            counts.alreadyOff += 1
            log("already off: \(appName)")
            try? ensureOverview()
            continue
        }

        if dryRun {
            counts.wouldChange += 1
            print("would disable: \(appName)")
            try? ensureOverview()
            continue
        }

        _ = press(checkbox)
        Thread.sleep(forTimeInterval: 0.5)
        let after = value(of: checkbox)

        if after == "0" {
            counts.changed += 1
            print("disabled: \(appName)")
        } else {
            counts.failed += 1
            print("failed: \(appName) (checkbox stayed at \(after); opened as \(currentLabel))")
        }

        try? ensureOverview()
    }

    return counts
}

func printSummary(_ counts: Counts) {
    print("")
    print("Summary")
    if dryRun {
        print("- would change: \(counts.wouldChange)")
    } else {
        print("- changed: \(counts.changed)")
    }
    print("- already off: \(counts.alreadyOff)")
    print("- skipped excluded: \(counts.skippedExcluded)")
    print("- skipped locked: \(counts.skippedLocked)")
    print("- failed: \(counts.failed)")
}

guard AXIsProcessTrusted() else {
    fputs("Accessibility access is required for System Settings automation. Enable it for your terminal app in System Settings > Privacy & Security > Accessibility.\n", stderr)
    exit(2)
}

launchNotificationsPane()

do {
    try ensureOverview()
    guard let window = systemSettingsWindow() else {
        throw NSError(domain: "NotificationSounds", code: 6, userInfo: [NSLocalizedDescriptionKey: "System Settings did not open Notifications"])
    }

    let entries = overviewEntries(in: window)

    if listOnly {
        print("Notification entries")
        for entry in entries {
            print("- \(entry.label)")
        }
        exit(0)
    }

    let counts = try process(entries: entries)
    try? ensureOverview()
    printSummary(counts)
    exit(0)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
SWIFT

DOTFILES_NOTIFICATION_DRY_RUN=$([[ "$dry_run" == true ]] && printf '1' || printf '0') \
DOTFILES_NOTIFICATION_VERBOSE=$([[ "$verbose" == true ]] && printf '1' || printf '0') \
DOTFILES_NOTIFICATION_LIST_ONLY=$([[ "$list_only" == true ]] && printf '1' || printf '0') \
DOTFILES_NOTIFICATION_EXCLUDE_FILE="$exclude_file" \
/usr/bin/swift "$swift_file"
