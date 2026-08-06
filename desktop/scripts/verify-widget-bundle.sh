#!/bin/zsh

set -euo pipefail

readonly EXPECTED_APP_IDENTIFIER="com.prabhavalabs.agentmeter.desktop"
readonly EXPECTED_WIDGET_IDENTIFIER="com.prabhavalabs.agentmeter.desktop.widget"
readonly EXPECTED_EXTENSION_POINT="com.apple.widgetkit-extension"
readonly SHARED_APP_GROUP="group.com.prabhavalabs.agentmeter.shared"

fail() {
    print -u2 -- "error: $1"
    exit 1
}

usage() {
    print -u2 -- "usage: ${0:t} [--community] [--] <AgentMeter.app>"
    exit 64
}

community_mode=false
app_bundle=""

while (( $# > 0 )); do
    case "$1" in
        --community)
            [[ "${community_mode}" == false ]] || usage
            community_mode=true
            shift
            ;;
        --)
            shift
            (( $# == 1 )) || usage
            app_bundle="$1"
            shift
            ;;
        -*)
            usage
            ;;
        *)
            [[ -z "${app_bundle}" ]] || usage
            app_bundle="$1"
            shift
            ;;
    esac
done

[[ -n "${app_bundle}" ]] || usage
[[ -d "${app_bundle}" ]] || fail "app bundle not found at ${app_bundle}"

readonly plugins_directory="${app_bundle}/Contents/PlugIns"

if [[ "${community_mode}" == true ]]; then
    [[ ! -e "${plugins_directory}" ]] || \
        fail "community app must not contain ${plugins_directory}"
    print -- "Verified app-only community bundle: ${app_bundle}"
    exit 0
fi

readonly app_info_plist="${app_bundle}/Contents/Info.plist"
readonly widget_bundle="${plugins_directory}/AgentMeterWidgets.appex"
readonly widget_info_plist="${widget_bundle}/Contents/Info.plist"

[[ -f "${app_info_plist}" ]] || fail "app Info.plist not found at ${app_info_plist}"
[[ -d "${widget_bundle}" ]] || fail "widget extension not found at ${widget_bundle}"
[[ -f "${widget_info_plist}" ]] || \
    fail "widget Info.plist not found at ${widget_info_plist}"

plist_value() {
    local key="$1"
    local plist="$2"
    local value
    value=$(/usr/libexec/PlistBuddy -c "Print :${key}" "${plist}" 2>/dev/null) || \
        fail "missing ${key} in ${plist}"
    print -r -- "${value}"
}

app_identifier=$(plist_value "CFBundleIdentifier" "${app_info_plist}")
[[ "${app_identifier}" == "${EXPECTED_APP_IDENTIFIER}" ]] || \
    fail "unexpected app bundle identifier '${app_identifier}'; expected '${EXPECTED_APP_IDENTIFIER}'"

widget_identifier=$(plist_value "CFBundleIdentifier" "${widget_info_plist}")
[[ "${widget_identifier}" == "${EXPECTED_WIDGET_IDENTIFIER}" ]] || \
    fail "unexpected widget bundle identifier '${widget_identifier}'; expected '${EXPECTED_WIDGET_IDENTIFIER}'"

extension_point=$(plist_value \
    "NSExtension:NSExtensionPointIdentifier" \
    "${widget_info_plist}")
[[ "${extension_point}" == "${EXPECTED_EXTENSION_POINT}" ]] || \
    fail "unexpected widget extension point '${extension_point}'; expected '${EXPECTED_EXTENSION_POINT}'"

app_signed=false
widget_signed=false
[[ -f "${app_bundle}/Contents/_CodeSignature/CodeResources" ]] && app_signed=true
[[ -f "${widget_bundle}/Contents/_CodeSignature/CodeResources" ]] && widget_signed=true

entitlements_contain_shared_group() {
    local bundle="$1"
    local label="$2"
    local entitlements_file
    local groups_json

    entitlements_file=$(mktemp "${TMPDIR:-/tmp}/agentmeter-entitlements.XXXXXX")
    if ! codesign -d --entitlements :- "${bundle}" > "${entitlements_file}" 2>/dev/null; then
        rm -f -- "${entitlements_file}"
        fail "unable to read ${label} entitlements from ${bundle}"
    fi
    if ! groups_json=$(plutil -extract \
        'com\.apple\.security\.application-groups' \
        json \
        -o - \
        "${entitlements_file}" 2>/dev/null); then
        rm -f -- "${entitlements_file}"
        fail "${label} entitlements do not declare ${SHARED_APP_GROUP}"
    fi
    rm -f -- "${entitlements_file}"

    [[ "${groups_json}" == *\"${SHARED_APP_GROUP}\"* ]] || \
        fail "${label} entitlements do not declare ${SHARED_APP_GROUP}"
}

if [[ "${app_signed}" == true || "${widget_signed}" == true ]]; then
    [[ "${app_signed}" == true ]] || \
        fail "widget extension is signed but outer app is unsigned"
    [[ "${widget_signed}" == true ]] || \
        fail "outer app is signed but widget extension is unsigned"

    codesign --verify --strict --verbose=2 "${widget_bundle}" || \
        fail "widget extension signature verification failed for ${widget_bundle}"
    codesign --verify --strict --verbose=2 "${app_bundle}" || \
        fail "outer app signature verification failed for ${app_bundle}"
    entitlements_contain_shared_group "${app_bundle}" "app"
    entitlements_contain_shared_group "${widget_bundle}" "widget extension"
fi

print -- "Verified AgentMeter widget bundle: ${widget_bundle}"
