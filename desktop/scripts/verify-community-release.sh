#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
DESKTOP_ROOT=${SCRIPT_DIRECTORY:h}
DMG_PATH=${1:-}

if [[ -z "${DMG_PATH}" ]]; then
  DMG_CANDIDATES=(${DESKTOP_ROOT}/dist/AgentMeter-*-macOS-*-community.dmg(Nom[1]))
  DMG_PATH=${DMG_CANDIDATES[1]:-}
fi
if [[ -z "${DMG_PATH}" || ! -f "${DMG_PATH}" ]]; then
  echo "Community DMG not found. Pass its path or run create-community-dmg.sh first." >&2
  exit 1
fi

CHECKSUM_PATH=${DMG_PATH}.sha256
if [[ ! -f "${CHECKSUM_PATH}" ]]; then
  echo "Checksum not found at ${CHECKSUM_PATH}." >&2
  exit 1
fi

MOUNT_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/agentmeter-verify.XXXXXX")
mounted=false
cleanup() {
  if [[ "${mounted}" == true ]]; then
    hdiutil detach "${MOUNT_DIRECTORY}" -quiet || true
  fi
  rmdir "${MOUNT_DIRECTORY}" 2>/dev/null || true
}
trap cleanup EXIT

(cd "${DMG_PATH:h}" && shasum -a 256 -c "${CHECKSUM_PATH:t}")
codesign --verify --verbose=2 "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"
hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_DIRECTORY}" "${DMG_PATH}" -quiet
mounted=true

APP_BUNDLE=${MOUNT_DIRECTORY}/AgentMeter.app
NOTICE=${MOUNT_DIRECTORY}/COMMUNITY-BUILD.txt
if [[ ! -d "${APP_BUNDLE}" || ! -L "${MOUNT_DIRECTORY}/Applications" || ! -f "${NOTICE}" ]]; then
  echo "The DMG is missing the app, Applications shortcut, or community notice." >&2
  exit 1
fi

INFO_PLIST=${APP_BUNDLE}/Contents/Info.plist
MODE=$(/usr/libexec/PlistBuddy -c 'Print :AgentMeterDistributionMode' "${INFO_PLIST}")
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")
if [[ "${MODE}" != "community" ]]; then
  echo "The packaged app is not marked as a community build." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
if ! codesign -dvv "${APP_BUNDLE}" 2>&1 | grep '^Signature=adhoc$' >/dev/null; then
  echo "The community app does not have the expected ad-hoc signature." >&2
  exit 1
fi

HELPER=${APP_BUNDLE}/Contents/Resources/AgentMeterBridge/AgentMeterBridge
HELPER_VERSION=$("${HELPER}" --version)
if [[ "${HELPER_VERSION}" != "AgentMeter ${VERSION}" ]]; then
  echo "App ${VERSION} and bundled helper '${HELPER_VERSION}' do not match." >&2
  exit 1
fi

if spctl --assess --type execute "${APP_BUNDLE}" >/dev/null 2>&1; then
  echo "Expected Gatekeeper to require manual approval for the community build." >&2
  exit 1
fi

echo "Verified AgentMeter ${VERSION} community DMG: ${DMG_PATH}"
echo "Gatekeeper rejection is expected because this build is not Developer ID signed or notarized."
