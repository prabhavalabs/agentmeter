#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
DESKTOP_ROOT=${SCRIPT_DIRECTORY:h}
OUTPUT_ROOT=${DESKTOP_ROOT}/dist
APP_BUNDLE=${OUTPUT_ROOT}/AgentMeter.app
PACKAGE_WORK=${DESKTOP_ROOT}/.build/app-package
ICONSET=${PACKAGE_WORK}/AppIcon.iconset
ICON_SOURCE=${DESKTOP_ROOT}/Resources/AppIcon-1024.png
SIGNING_IDENTITY=${CODE_SIGN_IDENTITY:--}
BRIDGE_PYTHON=${AGENTMETER_PACKAGE_PYTHON:-${DESKTOP_ROOT:h}/.venv/bin/python}
APP_VERSION=${AGENTMETER_APP_VERSION:-0.1.2}
APP_BUILD=${AGENTMETER_APP_BUILD:-1}
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  DISTRIBUTION_MODE=${AGENTMETER_DISTRIBUTION_MODE:-community}
else
  DISTRIBUTION_MODE=${AGENTMETER_DISTRIBUTION_MODE:-managed}
fi
if [[ "${DISTRIBUTION_MODE}" != "community" && "${DISTRIBUTION_MODE}" != "managed" ]]; then
  echo "AGENTMETER_DISTRIBUTION_MODE must be 'community' or 'managed'." >&2
  exit 1
fi
if [[ ! "${APP_VERSION}" =~ "^[0-9]+\.[0-9]+\.[0-9]+$" ]]; then
  echo "AGENTMETER_APP_VERSION must use numeric major.minor.patch format." >&2
  exit 1
fi
if [[ ! "${APP_BUILD}" =~ "^[1-9][0-9]*$" ]]; then
  echo "AGENTMETER_APP_BUILD must be a positive integer." >&2
  exit 1
fi

if [[ ! -x "${BRIDGE_PYTHON}" ]]; then
  echo "AgentMeter packaging requires ${BRIDGE_PYTHON}. Run 'make setup' first." >&2
  exit 1
fi
if ! "${BRIDGE_PYTHON}" -m PyInstaller --version >/dev/null 2>&1; then
  echo "PyInstaller is missing. Run 'make setup' or install the package extra." >&2
  exit 1
fi

swift build --package-path "${DESKTOP_ROOT}" --configuration release

rm -rf "${PACKAGE_WORK}"
mkdir -p "${ICONSET}"
VERSION_HOOK=${PACKAGE_WORK}/agentmeter-version.py
print -r -- "import agentmeter_host
agentmeter_host.__version__ = \"${APP_VERSION}\"" > "${VERSION_HOOK}"
sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET}/icon_512x512.png" >/dev/null
cp "${ICON_SOURCE}" "${ICONSET}/icon_512x512@2x.png"
iconutil --convert icns "${ICONSET}" --output "${PACKAGE_WORK}/AppIcon.icns"

PYINSTALLER_SIGNING=()
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  PYINSTALLER_SIGNING=(--codesign-identity "${SIGNING_IDENTITY}")
fi
"${BRIDGE_PYTHON}" -m PyInstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name AgentMeterBridge \
  --distpath "${PACKAGE_WORK}/bridge-dist" \
  --workpath "${PACKAGE_WORK}/bridge-build" \
  --specpath "${PACKAGE_WORK}" \
  --runtime-hook "${VERSION_HOOK}" \
  --noupx \
  --exclude-module _pytest \
  --exclude-module pytest \
  --exclude-module click \
  --exclude-module colorama \
  --exclude-module chardet \
  --exclude-module pygments \
  "${PYINSTALLER_SIGNING[@]}" \
  "${DESKTOP_ROOT}/bridge_entry.py"

rm -rf "${APP_BUNDLE}"
mkdir -p \
  "${APP_BUNDLE}/Contents/MacOS" \
  "${APP_BUNDLE}/Contents/Resources" \
  "${APP_BUNDLE}/Contents/Resources/fixtures" \
  "${APP_BUNDLE}/Contents/Library/LaunchAgents"
cp "${DESKTOP_ROOT}/.build/release/AgentMeter" "${APP_BUNDLE}/Contents/MacOS/AgentMeter"
cp "${DESKTOP_ROOT}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
  "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_BUILD}" \
  "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AgentMeterDistributionMode string ${DISTRIBUTION_MODE}" \
  "${APP_BUNDLE}/Contents/Info.plist"
cp "${PACKAGE_WORK}/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "${DESKTOP_ROOT:h}/config.example.toml" "${APP_BUNDLE}/Contents/Resources/config.example.toml"
cp "${DESKTOP_ROOT:h}/LICENSE" "${APP_BUNDLE}/Contents/Resources/LICENSE.txt"
cp "${DESKTOP_ROOT:h}/THIRD_PARTY_NOTICES.md" \
  "${APP_BUNDLE}/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp \
  "${DESKTOP_ROOT:h}/fixtures/desktop-ipc-status-v1.json" \
  "${DESKTOP_ROOT:h}/fixtures/desktop-ipc-settings-v1.json" \
  "${APP_BUNDLE}/Contents/Resources/fixtures/"
cp \
  "${DESKTOP_ROOT}/Resources/com.prabhavalabs.agentmeter.bridge.plist" \
  "${APP_BUNDLE}/Contents/Library/LaunchAgents/com.prabhavalabs.agentmeter.bridge.plist"
ditto \
  "${PACKAGE_WORK}/bridge-dist/AgentMeterBridge" \
  "${APP_BUNDLE}/Contents/Resources/AgentMeterBridge"
ln -s \
  AgentMeterBridge \
  "${APP_BUNDLE}/Contents/Resources/AgentMeterBridge/agentmeter-claude-probe"

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  codesign --force --options runtime --timestamp=none --sign - "${APP_BUNDLE}"
else
  codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
plutil -lint "${APP_BUNDLE}/Contents/Info.plist"

if otool -L "${APP_BUNDLE}/Contents/Resources/AgentMeterBridge/AgentMeterBridge" \
    | tail -n +2 \
    | grep -E '/(Homebrew|\.venv|arduino-token-usage-monitor)/' >/dev/null; then
  echo "The bundled bridge contains a development-only library path." >&2
  exit 1
fi

BUNDLE_SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')

echo "Created ${APP_BUNDLE} (${BUNDLE_SIZE})"
