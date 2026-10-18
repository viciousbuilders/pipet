#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
mkdir -p .build/tests
swiftc -swift-version 6 -parse-as-library -warnings-as-errors \
  CodexVoice/HotkeyMonitor.swift CodexVoice/DebugLogger.swift \
  Tests/HotkeyGestureTests.swift -o .build/tests/hotkey-gesture
.build/tests/hotkey-gesture
