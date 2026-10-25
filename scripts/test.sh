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
