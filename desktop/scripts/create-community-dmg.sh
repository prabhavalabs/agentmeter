#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
DESKTOP_ROOT=${SCRIPT_DIRECTORY:h}
APP_BUNDLE=${1:-${DESKTOP_ROOT}/dist/AgentMeter.app}
OUTPUT_DIRECTORY=${2:-${DESKTOP_ROOT}/dist}

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "AgentMeter bundle not found at ${APP_BUNDLE}." >&2
  exit 1
fi

INFO_PLIST=${APP_BUNDLE}/Contents/Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")
DISTRIBUTION_MODE=$(/usr/libexec/PlistBuddy -c 'Print :AgentMeterDistributionMode' "${INFO_PLIST}")
ARCHITECTURES=($(lipo -archs "${APP_BUNDLE}/Contents/MacOS/AgentMeter"))
ARCHITECTURE=${(j:-:)ARCHITECTURES}
DMG_PATH=${OUTPUT_DIRECTORY}/AgentMeter-${VERSION}-macOS-${ARCHITECTURE}-community.dmg
CHECKSUM_PATH=${DMG_PATH}.sha256
STAGING_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/agentmeter-dmg.XXXXXX")

cleanup() {
  rm -rf -- "${STAGING_DIRECTORY}"
}
trap cleanup EXIT

if [[ "${DISTRIBUTION_MODE}" != "community" ]]; then
  echo "Expected a community app bundle, found distribution mode '${DISTRIBUTION_MODE}'." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
mkdir -p "${OUTPUT_DIRECTORY}" "${STAGING_DIRECTORY}/AgentMeter ${VERSION}"
ditto "${APP_BUNDLE}" "${STAGING_DIRECTORY}/AgentMeter ${VERSION}/AgentMeter.app"
ln -s /Applications "${STAGING_DIRECTORY}/AgentMeter ${VERSION}/Applications"

print -r -- "AgentMeter ${VERSION} community build

This open-source build is ad-hoc signed and is not notarized by Apple.

Install:
1. Drag AgentMeter.app to the Applications shortcut.
2. Control-click AgentMeter in Applications and choose Open.
3. Confirm Open when macOS displays the security notice.

The bundled bridge runs while AgentMeter is open. Closing the main window keeps
the menu-bar app and bridge running; choosing Quit AgentMeter stops both.

Source and issue tracker: https://github.com/prabhavalabs/agentmeter" \
  > "${STAGING_DIRECTORY}/AgentMeter ${VERSION}/COMMUNITY-BUILD.txt"

rm -f -- "${DMG_PATH}" "${CHECKSUM_PATH}"
hdiutil create \
  -volname "AgentMeter ${VERSION}" \
  -srcfolder "${STAGING_DIRECTORY}/AgentMeter ${VERSION}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "${DMG_PATH}"
codesign --force --timestamp=none --sign - "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"
(cd "${OUTPUT_DIRECTORY}" && shasum -a 256 "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}")

echo "Created ${DMG_PATH}"
echo "Created ${CHECKSUM_PATH}"
