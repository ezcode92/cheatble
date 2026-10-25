#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Cheatble.app"
if [[ ! -x "$APP/Contents/MacOS/Cheatble" ]]; then
    printf 'Build the app first: bash scripts/build-app.sh\n' >&2
    exit 1
fi
OUT="$(mktemp -d /private/tmp/cheatble-smoke.XXXXXX)"
# Relocation verifies resource lookup at an arbitrary install path.
ditto "$APP" "$OUT/Cheatble.app"
# Smoke runs must never share the installed app's Accessibility identity.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.cheatble.smoke' "$OUT/Cheatble.app/Contents/Info.plist"
codesign --remove-signature "$OUT/Cheatble.app"
codesign --force --sign - --identifier app.cheatble.smoke --timestamp=none "$OUT/Cheatble.app"
codesign --verify --strict "$OUT/Cheatble.app"
"$OUT/Cheatble.app/Contents/MacOS/Cheatble" --validate-bundle
"$OUT/Cheatble.app/Contents/MacOS/Cheatble" --smoke-test "$OUT" &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for ((i=0; i<60; i++)); do
    if [[ -f "$OUT/report.json" || -f "$OUT/error.txt" ]]; then break; fi
    if ! kill -0 "$PID" 2>/dev/null; then break; fi
    sleep 1
done
python3 - "$OUT" <<'PY'
import json, pathlib, sys
directory = pathlib.Path(sys.argv[1])
report_path = directory / "report.json"
if not report_path.exists():
    error = directory / "error.txt"
    raise SystemExit(error.read_text() if error.exists() else "No smoke report; a logged-in macOS GUI session is required.")
report = json.loads(report_path.read_text())
assert report["catalogCount"] == 126, report
assert report["macOSCount"] == 68, report
assert report["searchCount"] > 0, report
assert report["windowAlpha"] == report["backgroundOpacity"], report
assert report["transparentWindowAlpha"] == 0.2, report
assert report["resizedWidth"] == 240 and report["resizedHeight"] == 360, report
assert report["bundledPackCount"] == 8 and report["bundledPackEntries"] == 238, report
assert report["savedSafariCount"] == 31, report
for key in ["nonactivatingPanel", "didNotActivate", "didNotBecomeKey", "floating",
            "startupPackPrefixConflictRejected", "startupBundledPacksLoaded", "packConflictKeepsPreviousShortcut",
            "navigationPackPrefixConflictRejected",
            "persistedFavorite", "persistedLearned", "learnedHidden",
            "activeAppDetected", "activeAppMatchesWorkspace",
            "globalHotKeyRegistered", "hotKeyHides", "hotKeyShows", "hotKeyRepeatIgnored",
            "hotKeyDuplicateRejected", "hotKeyFailedChangeKeepsOld", "hotKeyDisableWorks", "hotKeyReenableWorks",
            "directResizePersists", "visibleResizeHandle", "resizeAcceptsFirstClick", "requestedAppsSelectable",
            "savedSelectionSurvivesActivation", "savedSelectionPersists", "activeAppCanBeSaved",
            "installedPackAutoReloads", "requestTargetsSelection", "emptyAppCanRequestPack",
            "activeSelectionFollowsAppChanges", "pickerExcludesActiveApp", "savedSelectionKeepsListAndFilters",
            "savedSelectionDoesNotBecomeAutomatic", "systemSelectionKeepsListAndFilters",
            "iconPickerOpens", "iconPickerDoesNotActivateApp", "iconPickerSelectionClosesAndPins", "hidingSheetDismissesPicker",
            "navigationHotKeysRegistered", "hotKeyIdentitiesAreDistinct", "navigationSelectsActiveApp",
            "navigationSelectsSystem", "navigationOpensSavedPicker", "navigationClosesSavedPicker", "internalHotKeyConflictsRejected",
            "pickerGetsKeyboardFocus", "pickerLeftStopsAtFirst", "pickerRightMovesOne", "pickerDownMovesRow", "pickerUpMovesRow",
            "pickerEmptyReturnDoesNothing", "pickerSearchUpdatesHighlight", "pickerReturnChoosesApp", "pickerReopensAfterToggle",
            "pickerRefocusesOnReopen", "pickerEscapeCloses", "pickerReturnsKeyboardFocus",
            "navigationCanDisableAndReenable", "navigationPreservesForegroundApp", "moveHandleAcceptsFirstClick",
            "movedPositionPersists", "twoColumnsAtMediumWidth", "threeColumnsAtWideWidth", "managementScopeIndependentOfOverlay"]:
    assert report[key], (key, report)
for name in ["overlay", "overlay-small", "settings", "editor", "saved-app", "tmux", "google-search", "added-app", "empty-app", "app-picker", "app-picker-search", "overlay-2col", "overlay-3col", "app-shortcut-settings", "excel", "word", "powerpoint"]:
    assert (directory / (name + ".png")).stat().st_size > 1000
print(json.dumps(report, ensure_ascii=False, indent=2))
print(f"Screenshot: {directory / 'overlay.png'}")
PY
mkdir -p "$ROOT/dist/smoke"
cp "$OUT/report.json" "$ROOT/dist/smoke/report.json"
cp "$OUT/"*.png "$ROOT/dist/smoke/"
