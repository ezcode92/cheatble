#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CACHE="$(printenv CHEATBLE_CACHE_DIR || true)"
if [[ -z "$CACHE" ]]; then CACHE="$ROOT/.build/cache"; fi
mkdir -p "$CACHE/clang" "$CACHE/swiftpm"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
swift test --disable-xctest --enable-swift-testing --disable-sandbox --cache-path "$CACHE/swiftpm"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-publish-build.py
# Link a small nonvisual regression runner against the freshly built core.
BIN="$(swift build --disable-sandbox --cache-path "$CACHE/swiftpm" --show-bin-path)"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$CACHE/clang" -I "$BIN/Modules" \
    Sources/Cheatble/AccessibilityReader.swift Sources/Cheatble/ActiveAppTracker.swift \
    Sources/Cheatble/AppPackObserver.swift Sources/Cheatble/AppModel.swift \
    Tests/AppBehavior/main.swift "$BIN"/CheatbleCore.build/*.o -o "$BIN/app-behavior-tests"
"$BIN/app-behavior-tests"
