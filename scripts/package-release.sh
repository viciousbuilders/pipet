#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
./scripts/build-app.sh --universal
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/Pipet.app/Contents/Info.plist)"
RELEASE_DIR="${ROOT_DIR}/dist/Pipet-${APP_VERSION}"
if [[ -e "${RELEASE_DIR}" ]]; then
  echo "Release directory already exists: ${RELEASE_DIR}. Increase the version or move it aside." >&2
  exit 1
fi
mkdir -p "${RELEASE_DIR}" ".build/dmg-${APP_VERSION}"
ditto .build/Pipet.app "${RELEASE_DIR}/Pipet.app"
cp docs/START-HERE.txt "${RELEASE_DIR}/START-HERE.txt"
cp LICENSE "${RELEASE_DIR}/LICENSE.txt"
ditto "${RELEASE_DIR}/Pipet.app" ".build/dmg-${APP_VERSION}/Pipet.app"
cp "${RELEASE_DIR}/START-HERE.txt" ".build/dmg-${APP_VERSION}/START-HERE.txt"
cp LICENSE ".build/dmg-${APP_VERSION}/LICENSE.txt"
ln -s /Applications ".build/dmg-${APP_VERSION}/Applications"
hdiutil create -volname Pipet -srcfolder ".build/dmg-${APP_VERSION}" -format UDZO "${RELEASE_DIR}/Pipet-${APP_VERSION}-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "${RELEASE_DIR}/Pipet.app" "${RELEASE_DIR}/Pipet-${APP_VERSION}-universal.zip"
if [[ -n "${PIPET_SIGNING_IDENTITY:-}" ]]; then
  codesign --sign "${PIPET_SIGNING_IDENTITY}" --timestamp "${RELEASE_DIR}/Pipet-${APP_VERSION}-universal.dmg"
fi
if [[ -n "${PIPET_NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${PIPET_SIGNING_IDENTITY:-}" ]]; then
    echo "Notarization requires PIPET_SIGNING_IDENTITY." >&2
    exit 1
  fi
  "${ROOT_DIR}/scripts/notarize-release.sh" "${RELEASE_DIR}"
fi
(cd "${RELEASE_DIR}" && shasum -a 256 Pipet-*.dmg Pipet-*.zip > SHA256SUMS.txt)
echo "Share ${RELEASE_DIR}/Pipet-${APP_VERSION}-universal.dmg"
