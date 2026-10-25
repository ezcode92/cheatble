#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CACHE="$(printenv CHEATBLE_CACHE_DIR || true)"
if [[ -z "$CACHE" ]]; then CACHE="$ROOT/.build/cache"; fi
mkdir -p "$CACHE/clang" "$CACHE/swiftpm" "$ROOT/dist"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
swift build -c release --disable-sandbox --cache-path "$CACHE/swiftpm"
BIN="$(swift build -c release --disable-sandbox --cache-path "$CACHE/swiftpm" --show-bin-path)"
STAGE="$(mktemp -d "$ROOT/dist/.build-stage.XXXXXX")"
KEEP_STAGE=0
cleanup() {
    if [[ "$KEEP_STAGE" == 0 ]]; then rm -rf "$STAGE";
    else printf 'Build files preserved for recovery: %s\n' "$STAGE" >&2; fi
}
trap cleanup EXIT
APP="$STAGE/Cheatble.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Cheatble" "$APP/Contents/MacOS/Cheatble"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/CheatbleCore/Resources/Shortcuts.json" "$APP/Contents/Resources/Shortcuts.json"
ditto "$ROOT/Sources/CheatbleCore/Resources/Packs" "$APP/Contents/Resources/Packs"
swift -module-cache-path "$CACHE/clang" "$ROOT/scripts/make-icon.swift" "$ROOT/.build/AppIcon.iconset" "$ROOT/Resources/AppIcon.png"
iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
python3 "$ROOT/scripts/sign-app.py" "$APP"
"$APP/Contents/MacOS/Cheatble" --validate-bundle
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/Cheatble.zip"
# Publish only a complete, validated build. Preserve backups if rollback fails.
KEEP_STAGE=1
python3 "$ROOT/scripts/publish-build.py" "$STAGE" "$ROOT/dist"
KEEP_STAGE=0
printf 'Built: %s\n' "$ROOT/dist/Cheatble.app"
