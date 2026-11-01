#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
mkdir -p .build/tests
APP_SOURCES=()
for SOURCE in CodexVoice/*.swift; do
  if [[ "${SOURCE}" != "CodexVoice/CodexVoiceApp.swift" ]]; then
    APP_SOURCES+=("${SOURCE}")
  fi
done
swiftc -O -swift-version 6 -parse-as-library -warnings-as-errors \
  "${APP_SOURCES[@]}" Tests/MediaPlaybackTests.swift -o .build/tests/media-playback
.build/tests/media-playback
