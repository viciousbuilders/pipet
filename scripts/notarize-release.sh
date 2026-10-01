#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${1:?Usage: notarize-release.sh /path/to/release-directory}"
APP="${RELEASE_DIR}/Pipet.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
DMG="${RELEASE_DIR}/Pipet-${APP_VERSION}-universal.dmg"
PROFILE="${PIPET_NOTARY_PROFILE:-Pipet}"
codesign --verify --deep --strict "${APP}"
if ! codesign -dv --verbose=2 "${APP}" 2>&1 | rg '^Authority=Developer ID Application:' >/dev/null; then
  echo "A Developer ID Application signature is required." >&2
  exit 1
fi
xcrun notarytool history --keychain-profile "${PROFILE}" >/dev/null
mkdir -p "${ROOT_DIR}/.build/notarization"
RESULT="${ROOT_DIR}/.build/notarization/Pipet-${APP_VERSION}.json"
xcrun notarytool submit "${DMG}" --keychain-profile "${PROFILE}" --wait --output-format json > "${RESULT}"
python3 - "${RESULT}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
print('Apple notarization:', result.get('status'), 'Submission:', result.get('id'))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the submission log before sharing.')
PY
xcrun stapler staple "${APP}"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${APP}"
xcrun stapler validate "${DMG}"
codesign --verify --deep --strict "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${RELEASE_DIR}/Pipet-${APP_VERSION}-universal.zip"
(cd "${RELEASE_DIR}" && shasum -a 256 Pipet-*.dmg Pipet-*.zip > SHA256SUMS.txt)
echo "Apple-notarized release ready: ${DMG}"
