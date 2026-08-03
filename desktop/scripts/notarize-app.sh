#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
DESKTOP_ROOT=${SCRIPT_DIRECTORY:h}
APP_BUNDLE=${1:-${DESKTOP_ROOT}/dist/AgentMeter.app}
NOTARY_PROFILE=${NOTARY_KEYCHAIN_PROFILE:-}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_BUNDLE}/Contents/Info.plist")
SUBMISSION_ARCHIVE=${DESKTOP_ROOT}/dist/AgentMeter-notarization.zip
RELEASE_ARCHIVE=${DESKTOP_ROOT}/dist/AgentMeter-${VERSION}-macOS.zip

if [[ -z "${NOTARY_PROFILE}" ]]; then
  echo "Set NOTARY_KEYCHAIN_PROFILE to a notarytool keychain profile." >&2
  exit 1
fi
if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "AgentMeter bundle not found at ${APP_BUNDLE}." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${SUBMISSION_ARCHIVE}"
xcrun notarytool submit "${SUBMISSION_ARCHIVE}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${RELEASE_ARCHIVE}"

echo "Created ${RELEASE_ARCHIVE}"
