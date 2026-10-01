#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
BUILD_APP="${ROOT_DIR}/.build/Pipet.app"
BUNDLE_ID="au.vietbrosinaus.pipet"
mkdir -p "${BUILD_APP}/Contents/MacOS" "${BUILD_APP}/Contents/Resources" .build/release .build/Pipet.iconset

if [[ "${1:-}" == "--universal" ]]; then
  for APP_ARCH in arm64 x86_64; do
    swiftc -O -swift-version 6 -parse-as-library -target "${APP_ARCH}-apple-macosx14.0" CodexVoice/*.swift -o ".build/release/Pipet-${APP_ARCH}"
  done
  lipo -create .build/release/Pipet-arm64 .build/release/Pipet-x86_64 -output "${BUILD_APP}/Contents/MacOS/Pipet"
else
  swiftc -O -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx14.0" CodexVoice/*.swift -o "${BUILD_APP}/Contents/MacOS/Pipet"
fi

cp assets/PipetLogo.png "${BUILD_APP}/Contents/Resources/PipetLogo.png"
for ICON_SIZE in 16 32 128 256 512; do
  sips -z "${ICON_SIZE}" "${ICON_SIZE}" assets/PipetLogo.png --out ".build/Pipet.iconset/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
  RETINA_SIZE=$((ICON_SIZE * 2))
  sips -z "${RETINA_SIZE}" "${RETINA_SIZE}" assets/PipetLogo.png --out ".build/Pipet.iconset/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns .build/Pipet.iconset -o "${BUILD_APP}/Contents/Resources/Pipet.icns"
cp "${BUILD_APP}/Contents/Resources/Pipet.icns" assets/Pipet.icns
cp LICENSE "${BUILD_APP}/Contents/Resources/LICENSE.txt"
cp docs/START-HERE.txt "${BUILD_APP}/Contents/Resources/START-HERE.txt"
python3 - "${BUILD_APP}/Contents/Info.plist" <<'PLIST'
import plistlib, sys
with open('CodexVoice/Info.plist', 'rb') as source:
    info = plistlib.load(source)
info.update(CFBundleExecutable='Pipet', CFBundleIdentifier='au.vietbrosinaus.pipet', CFBundleName='Pipet')
with open(sys.argv[1], 'wb') as destination:
    plistlib.dump(info, destination)
PLIST
if [[ -n "${PIPET_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements CodexVoice/Pipet.entitlements --sign "${PIPET_SIGNING_IDENTITY}" --identifier "${BUNDLE_ID}" "${BUILD_APP}"
else
  codesign --force --options runtime --entitlements CodexVoice/Pipet.entitlements --sign - --identifier "${BUNDLE_ID}" "${BUILD_APP}"
fi
codesign --verify --deep --strict "${BUILD_APP}"
echo "Built ${BUILD_APP}"
