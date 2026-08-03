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

swift build --package-path "${DESKTOP_ROOT}" --configuration release

rm -rf "${PACKAGE_WORK}"
mkdir -p "${ICONSET}"
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

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${DESKTOP_ROOT}/.build/release/AgentMeter" "${APP_BUNDLE}/Contents/MacOS/AgentMeter"
cp "${DESKTOP_ROOT}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${PACKAGE_WORK}/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --timestamp=none --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
plutil -lint "${APP_BUNDLE}/Contents/Info.plist"

echo "Created ${APP_BUNDLE}"
