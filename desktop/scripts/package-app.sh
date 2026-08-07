#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
DESKTOP_ROOT=${SCRIPT_DIRECTORY:h}
OUTPUT_ROOT=${DESKTOP_ROOT}/dist
APP_BUNDLE=${OUTPUT_ROOT}/AgentMeter.app
PACKAGE_WORK=${DESKTOP_ROOT}/.build/app-package
XCODE_DERIVED_DATA=${DESKTOP_ROOT}/.build/xcode-derived
XCODE_APP_BUNDLE=${XCODE_DERIVED_DATA}/Build/Products/Release/AgentMeter.app
ICONSET=${PACKAGE_WORK}/AppIcon.iconset
ICON_SOURCE=${DESKTOP_ROOT}/Resources/AppIcon-1024.png
SIGNING_IDENTITY=${CODE_SIGN_IDENTITY:--}
BRIDGE_PYTHON=${AGENTMETER_PACKAGE_PYTHON:-${DESKTOP_ROOT:h}/.venv/bin/python}
APP_VERSION=${AGENTMETER_APP_VERSION:-0.2.0}
APP_BUILD=${AGENTMETER_APP_BUILD:-1}
SIGNING_TEMP_DIRECTORY=""

cleanup_signing_metadata() {
  if [[ -n "${SIGNING_TEMP_DIRECTORY}" && -d "${SIGNING_TEMP_DIRECTORY}" ]]; then
    rm -rf -- "${SIGNING_TEMP_DIRECTORY}"
  fi
}

on_hup() { exit 129; }
on_int() { exit 130; }
on_term() { exit 143; }

trap cleanup_signing_metadata EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  DISTRIBUTION_MODE=${AGENTMETER_DISTRIBUTION_MODE:-community}
else
  DISTRIBUTION_MODE=${AGENTMETER_DISTRIBUTION_MODE:-managed}
fi
if [[ "${DISTRIBUTION_MODE}" != "community" && "${DISTRIBUTION_MODE}" != "managed" ]]; then
  echo "AGENTMETER_DISTRIBUTION_MODE must be 'community' or 'managed'." >&2
  exit 1
fi
if [[ "${DISTRIBUTION_MODE}" == "managed" ]]; then
  if [[ -z "${AGENTMETER_DEVELOPMENT_TEAM:-}" ]]; then
    echo "AGENTMETER_DEVELOPMENT_TEAM is required for managed packaging." >&2
    exit 1
  fi
  if [[ -z "${AGENTMETER_APP_PROVISIONING_PROFILE:-}" ]]; then
    echo "AGENTMETER_APP_PROVISIONING_PROFILE is required for managed packaging." >&2
    exit 1
  fi
  if [[ -z "${AGENTMETER_WIDGET_PROVISIONING_PROFILE:-}" ]]; then
    echo "AGENTMETER_WIDGET_PROVISIONING_PROFILE is required for managed packaging." >&2
    exit 1
  fi
  if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    echo "CODE_SIGN_IDENTITY must name an Apple signing identity for managed packaging." >&2
    exit 1
  fi
  if [[ ! "${AGENTMETER_APP_PROVISIONING_PROFILE}" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]]; then
    echo "AGENTMETER_APP_PROVISIONING_PROFILE must be a provisioning profile UUID." >&2
    exit 1
  fi
  if [[ ! "${AGENTMETER_WIDGET_PROVISIONING_PROFILE}" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]]; then
    echo "AGENTMETER_WIDGET_PROVISIONING_PROFILE must be a provisioning profile UUID." >&2
    exit 1
  fi
fi
if [[ ! "${APP_VERSION}" =~ "^[0-9]+\.[0-9]+\.[0-9]+$" ]]; then
  echo "AGENTMETER_APP_VERSION must use numeric major.minor.patch format." >&2
  exit 1
fi
if [[ ! "${APP_BUILD}" =~ "^[1-9][0-9]*$" ]]; then
  echo "AGENTMETER_APP_BUILD must be a positive integer." >&2
  exit 1
fi

profile_value() {
  local key=$1
  local profile=$2
  local label=$3
  local value
  value=$(/usr/libexec/PlistBuddy -c "Print :${key}" "${profile}" 2>/dev/null) || {
    echo "The ${label} provisioning profile is missing ${key}." >&2
    exit 1
  }
  print -r -- "${value}"
}

decode_provisioning_profile() {
  local source_profile=$1
  local decoded_name=$2
  local label=$3
  local decoded_profile="${SIGNING_TEMP_DIRECTORY}/${decoded_name}.plist"

  if ! (umask 077; security cms -D -i "${source_profile}" > "${decoded_profile}" 2>/dev/null); then
    echo "Unable to decode the ${label} provisioning profile." >&2
    exit 1
  fi
  chmod 600 "${decoded_profile}"
  REPLY="${decoded_profile}"
}

resolve_installed_profile() {
  local expected_uuid=$1
  local label=$2
  local profile_directory
  local candidate
  local decoded_profile
  local candidate_uuid
  local index=0
  local -a profile_directories

  profile_directories=(
    "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "${HOME}/Library/MobileDevice/Provisioning Profiles"
  )

  for profile_directory in "${profile_directories[@]}"; do
    for candidate in \
      "${profile_directory}/${expected_uuid}.provisionprofile" \
      "${profile_directory}/${expected_uuid}.mobileprovision"; do
      if [[ -f "${candidate}" && ! -L "${candidate}" ]]; then
        REPLY="${candidate}"
        return
      fi
    done
  done

  for profile_directory in "${profile_directories[@]}"; do
    [[ -d "${profile_directory}" && ! -L "${profile_directory}" ]] || continue
    for candidate in "${profile_directory}"/*(N); do
      [[ -f "${candidate}" && ! -L "${candidate}" ]] || continue
      index=$(( index + 1 ))
      decoded_profile="${SIGNING_TEMP_DIRECTORY}/lookup-${label}-${index}.plist"
      if ! (umask 077; security cms -D -i "${candidate}" > "${decoded_profile}" 2>/dev/null); then
        continue
      fi
      chmod 600 "${decoded_profile}"
      candidate_uuid=$(/usr/libexec/PlistBuddy \
        -c 'Print :UUID' \
        "${decoded_profile}" 2>/dev/null) || continue
      if [[ "${candidate_uuid}" == "${expected_uuid}" ]]; then
        REPLY="${candidate}"
        return
      fi
    done
  done

  echo "Provisioning profile UUID ${expected_uuid} is not installed for the ${label} target." >&2
  exit 1
}

validate_provisioning_profile() {
  local source_profile=$1
  local expected_identifier=$2
  local label=$3
  local expected_uuid=$4
  local decoded_name=$5
  local decoded_profile
  local profile_team
  local profile_identifier
  local profile_groups
  local profile_uuid

  if [[ ! -f "${source_profile}" ]]; then
    echo "The ${label} provisioning profile is missing." >&2
    exit 1
  fi
  decode_provisioning_profile "${source_profile}" "${decoded_name}" "${label}"
  decoded_profile="${REPLY}"

  profile_uuid=$(profile_value "UUID" "${decoded_profile}" "${label}")
  if [[ "${profile_uuid}" != "${expected_uuid}" ]]; then
    echo "The ${label} provisioning profile has UUID ${profile_uuid}, not ${expected_uuid}." >&2
    exit 1
  fi

  profile_team=$(profile_value "TeamIdentifier:0" "${decoded_profile}" "${label}")
  if [[ "${profile_team}" != "${AGENTMETER_DEVELOPMENT_TEAM}" ]]; then
    echo "The ${label} provisioning profile belongs to team ${profile_team}, not ${AGENTMETER_DEVELOPMENT_TEAM}." >&2
    exit 1
  fi

  if ! profile_identifier=$(/usr/libexec/PlistBuddy \
    -c "Print :Entitlements:application-identifier" \
    "${decoded_profile}" 2>/dev/null); then
    profile_identifier=$(/usr/libexec/PlistBuddy \
      -c "Print :Entitlements:com.apple.application-identifier" \
      "${decoded_profile}" 2>/dev/null) || {
      echo "The ${label} provisioning profile has no application identifier." >&2
      exit 1
    }
  fi
  if [[ "${profile_identifier#*.}" != "${expected_identifier}" ]]; then
    echo "The ${label} provisioning profile targets ${profile_identifier#*.}, not ${expected_identifier}." >&2
    exit 1
  fi

  if ! profile_groups=$(plutil -extract \
    'Entitlements.com\.apple\.security\.application-groups' \
    json \
    -o - \
    "${decoded_profile}" 2>/dev/null) \
    || [[ "${profile_groups}" != *\"group.com.prabhavalabs.agentmeter.shared\"* ]]; then
    echo "The ${label} provisioning profile does not grant group.com.prabhavalabs.agentmeter.shared." >&2
    exit 1
  fi

}

verify_managed_bundle_versions() {
  local app=$1
  local widget="${app}/Contents/PlugIns/AgentMeterWidgets.appex"
  local app_version
  local app_build
  local widget_version
  local widget_build

  app_version=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "${app}/Contents/Info.plist")
  app_build=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleVersion' \
    "${app}/Contents/Info.plist")
  widget_version=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "${widget}/Contents/Info.plist")
  widget_build=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleVersion' \
    "${widget}/Contents/Info.plist")

  if [[ "${app_version}" != "${widget_version}" || "${app_build}" != "${widget_build}" ]]; then
    echo "Managed app version ${app_version} (${app_build}) does not match widget version ${widget_version} (${widget_build})." >&2
    exit 1
  fi
  if [[ "${app_version}" != "${APP_VERSION}" || "${app_build}" != "${APP_BUILD}" ]]; then
    echo "Managed bundle version ${app_version} (${app_build}) does not match requested version ${APP_VERSION} (${APP_BUILD})." >&2
    exit 1
  fi
}

if [[ "${DISTRIBUTION_MODE}" == "managed" ]]; then
  SIGNING_TEMP_DIRECTORY=$(mktemp -d \
    "${TMPDIR:-/tmp}/agentmeter-signing-metadata.XXXXXX")
  chmod 700 "${SIGNING_TEMP_DIRECTORY}"

  resolve_installed_profile "${AGENTMETER_APP_PROVISIONING_PROFILE}" "app"
  APP_PROVISIONING_PROFILE_PATH="${REPLY}"
  validate_provisioning_profile \
    "${APP_PROVISIONING_PROFILE_PATH}" \
    "com.prabhavalabs.agentmeter.desktop" \
    "app" \
    "${AGENTMETER_APP_PROVISIONING_PROFILE}" \
    "requested-app"

  resolve_installed_profile "${AGENTMETER_WIDGET_PROVISIONING_PROFILE}" "widget"
  WIDGET_PROVISIONING_PROFILE_PATH="${REPLY}"
  validate_provisioning_profile \
    "${WIDGET_PROVISIONING_PROFILE_PATH}" \
    "com.prabhavalabs.agentmeter.desktop.widget" \
    "widget" \
    "${AGENTMETER_WIDGET_PROVISIONING_PROFILE}" \
    "requested-widget"
fi

if [[ ! -x "${BRIDGE_PYTHON}" ]]; then
  echo "AgentMeter packaging requires ${BRIDGE_PYTHON}. Run 'make setup' first." >&2
  exit 1
fi
if ! "${BRIDGE_PYTHON}" -m PyInstaller --version >/dev/null 2>&1; then
  echo "PyInstaller is missing. Run 'make setup' or install the package extra." >&2
  exit 1
fi

rm -rf "${PACKAGE_WORK}"
mkdir -p "${ICONSET}"

if [[ "${DISTRIBUTION_MODE}" == "community" ]]; then
  swift build --package-path "${DESKTOP_ROOT}" --configuration release
else
  xcodebuild \
    -project "${DESKTOP_ROOT}/AgentMeter.xcodeproj" \
    -scheme AgentMeter \
    -configuration Release \
    -derivedDataPath "${XCODE_DERIVED_DATA}" \
    DEVELOPMENT_TEAM="${AGENTMETER_DEVELOPMENT_TEAM}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
    AGENTMETER_APP_PROVISIONING_PROFILE="${AGENTMETER_APP_PROVISIONING_PROFILE}" \
    AGENTMETER_WIDGET_PROVISIONING_PROFILE="${AGENTMETER_WIDGET_PROVISIONING_PROFILE}" \
    MARKETING_VERSION="${APP_VERSION}" \
    CURRENT_PROJECT_VERSION="${APP_BUILD}" \
    ENABLE_HARDENED_RUNTIME=YES \
    build

  if [[ ! -d "${XCODE_APP_BUNDLE}" ]]; then
    echo "The signed Xcode app was not produced at ${XCODE_APP_BUNDLE}." >&2
    exit 1
  fi
  verify_managed_bundle_versions "${XCODE_APP_BUNDLE}"
  validate_provisioning_profile \
    "${XCODE_APP_BUNDLE}/Contents/embedded.provisionprofile" \
    "com.prabhavalabs.agentmeter.desktop" \
    "app" \
    "${AGENTMETER_APP_PROVISIONING_PROFILE}" \
    "embedded-app"
  validate_provisioning_profile \
    "${XCODE_APP_BUNDLE}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/embedded.provisionprofile" \
    "com.prabhavalabs.agentmeter.desktop.widget" \
    "widget" \
    "${AGENTMETER_WIDGET_PROVISIONING_PROFILE}" \
    "embedded-widget"
  "${SCRIPT_DIRECTORY}/verify-widget-bundle.sh" "${XCODE_APP_BUNDLE}"
fi

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
if [[ "${DISTRIBUTION_MODE}" == "community" ]]; then
  mkdir -p \
    "${APP_BUNDLE}/Contents/MacOS" \
    "${APP_BUNDLE}/Contents/Resources" \
    "${APP_BUNDLE}/Contents/Resources/fixtures" \
    "${APP_BUNDLE}/Contents/Library/LaunchAgents"
  cp "${DESKTOP_ROOT}/.build/release/AgentMeter" "${APP_BUNDLE}/Contents/MacOS/AgentMeter"
  cp "${DESKTOP_ROOT}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
else
  mkdir -p "${OUTPUT_ROOT}"
  ditto "${XCODE_APP_BUNDLE}" "${APP_BUNDLE}"
  mkdir -p \
    "${APP_BUNDLE}/Contents/Resources/fixtures" \
    "${APP_BUNDLE}/Contents/Library/LaunchAgents"
fi
if [[ "${DISTRIBUTION_MODE}" == "community" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
    "${APP_BUNDLE}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_BUILD}" \
    "${APP_BUNDLE}/Contents/Info.plist"
else
  verify_managed_bundle_versions "${APP_BUNDLE}"
fi
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

if [[ "${DISTRIBUTION_MODE}" == "community" ]]; then
  codesign --force --options runtime --timestamp=none --sign - "${APP_BUNDLE}"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
  "${SCRIPT_DIRECTORY}/verify-widget-bundle.sh" --community "${APP_BUNDLE}"
else
  verify_managed_bundle_versions "${APP_BUNDLE}"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "${DESKTOP_ROOT}/Resources/AgentMeter.entitlements" \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_BUNDLE}"
  codesign --verify --strict --verbose=2 \
    "${APP_BUNDLE}/Contents/PlugIns/AgentMeterWidgets.appex"
  codesign --verify --strict --verbose=2 "${APP_BUNDLE}"
  "${SCRIPT_DIRECTORY}/verify-widget-bundle.sh" "${APP_BUNDLE}"
fi
plutil -lint "${APP_BUNDLE}/Contents/Info.plist"

if otool -L "${APP_BUNDLE}/Contents/Resources/AgentMeterBridge/AgentMeterBridge" \
    | tail -n +2 \
    | grep -E '/(Homebrew|\.venv|arduino-token-usage-monitor)/' >/dev/null; then
  echo "The bundled bridge contains a development-only library path." >&2
  exit 1
fi

BUNDLE_SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')

echo "Created ${APP_BUNDLE} (${BUNDLE_SIZE})"
