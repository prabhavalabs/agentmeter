#!/bin/zsh

set -euo pipefail

readonly EXPECTED_APP_IDENTIFIER="com.prabhavalabs.agentmeter.desktop"
readonly EXPECTED_WIDGET_IDENTIFIER="com.prabhavalabs.agentmeter.desktop.widget"
readonly EXPECTED_EXTENSION_POINT="com.apple.widgetkit-extension"
readonly SHARED_APP_GROUP="group.com.prabhavalabs.agentmeter.shared"
readonly -a FORBIDDEN_WIDGET_ENTITLEMENTS=(
    com.apple.security.network.client
    com.apple.security.network.server
    com.apple.security.device.bluetooth
    keychain-access-groups
    com.apple.security.files.user-selected.read-only
    com.apple.security.files.user-selected.read-write
    com.apple.security.files.downloads.read-only
    com.apple.security.files.downloads.read-write
    com.apple.security.files.bookmarks.app-scope
    com.apple.security.files.bookmarks.document-scope
    com.apple.security.files.absolute-path.read-only
    com.apple.security.files.absolute-path.read-write
    com.apple.security.assets.movies.read-only
    com.apple.security.assets.movies.read-write
    com.apple.security.assets.music.read-only
    com.apple.security.assets.music.read-write
    com.apple.security.assets.pictures.read-only
    com.apple.security.assets.pictures.read-write
)

temporary_directory=""

cleanup() {
    if [[ -n "${temporary_directory}" && -d "${temporary_directory}" ]]; then
        rm -rf -- "${temporary_directory}"
    fi
}

on_hup() { exit 129; }
on_int() { exit 130; }
on_term() { exit 143; }

trap cleanup EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM

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
[[ ! -L "${app_bundle}" ]] || fail "app bundle must not be a symlink: ${app_bundle}"

canonical_directory() {
    local directory="$1"
    (cd -P -- "${directory}" && pwd -P)
}

require_embedded_directory() {
    local directory="$1"
    local label="$2"
    local parent="$3"
    local canonical

    [[ ! -L "${directory}" ]] || fail "${label} must be a physical directory inside the app bundle: ${directory}"
    [[ -d "${directory}" ]] || fail "${label} not found at ${directory}"
    canonical=$(canonical_directory "${directory}") || fail "unable to resolve ${label} at ${directory}"
    [[ "${canonical}" == "${parent}"/* ]] || \
        fail "${label} resolves outside the app bundle: ${directory}"
    REPLY="${canonical}"
}

require_embedded_file() {
    local file="$1"
    local label="$2"
    local parent="$3"
    local container="$4"
    local canonical_parent
    local canonical

    [[ ! -L "${file}" ]] || fail "${label} must be a physical file inside ${container}: ${file}"
    [[ -f "${file}" ]] || fail "${label} not found at ${file}"
    canonical_parent=$(canonical_directory "${file:h}") || \
        fail "unable to resolve ${label} parent at ${file:h}"
    canonical="${canonical_parent}/${file:t}"
    [[ "${canonical}" == "${parent}"/* ]] || fail "${label} resolves outside ${container}: ${file}"
}

readonly canonical_app_bundle=$(canonical_directory "${app_bundle}")
readonly contents_directory="${app_bundle}/Contents"
require_embedded_directory "${contents_directory}" "app Contents" "${canonical_app_bundle}"
readonly canonical_contents_directory="${REPLY}"
readonly plugins_directory="${app_bundle}/Contents/PlugIns"

if [[ "${community_mode}" == true ]]; then
    [[ ! -e "${plugins_directory}" && ! -L "${plugins_directory}" ]] || \
        fail "community app must not contain ${plugins_directory}"
    print -- "Verified app-only community bundle: ${app_bundle}"
    exit 0
fi

readonly app_info_plist="${app_bundle}/Contents/Info.plist"
readonly widget_bundle="${plugins_directory}/AgentMeterWidgets.appex"
readonly widget_info_plist="${widget_bundle}/Contents/Info.plist"

require_embedded_file \
    "${app_info_plist}" \
    "app Info.plist" \
    "${canonical_contents_directory}" \
    "the app bundle"
require_embedded_directory "${plugins_directory}" "PlugIns" "${canonical_contents_directory}"
readonly canonical_plugins_directory="${REPLY}"
require_embedded_directory \
    "${widget_bundle}" \
    "widget extension" \
    "${canonical_plugins_directory}"
readonly canonical_widget_bundle="${REPLY}"
readonly widget_contents_directory="${widget_bundle}/Contents"
require_embedded_directory \
    "${widget_contents_directory}" \
    "widget Contents" \
    "${canonical_widget_bundle}"
readonly canonical_widget_contents_directory="${REPLY}"
require_embedded_file \
    "${widget_info_plist}" \
    "widget Info.plist" \
    "${canonical_widget_contents_directory}" \
    "the widget extension"

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
app_code_resources="${app_bundle}/Contents/_CodeSignature/CodeResources"
widget_code_resources="${widget_bundle}/Contents/_CodeSignature/CodeResources"
if [[ -e "${app_code_resources}" || -L "${app_code_resources}" ]]; then
    require_embedded_file \
        "${app_code_resources}" \
        "app CodeResources" \
        "${canonical_contents_directory}" \
        "the app bundle"
    app_signed=true
fi
if [[ -e "${widget_code_resources}" || -L "${widget_code_resources}" ]]; then
    require_embedded_file \
        "${widget_code_resources}" \
        "widget CodeResources" \
        "${canonical_widget_contents_directory}" \
        "the widget extension"
    widget_signed=true
fi

verify_entitlements() {
    local bundle="$1"
    local label="$2"
    local entitlements_file
    local groups_json
    local sandbox_value
    local forbidden_entitlement

    if [[ -z "${temporary_directory}" ]]; then
        temporary_directory=$(mktemp -d \
            "${TMPDIR:-/tmp}/agentmeter-widget-entitlements.XXXXXX")
        chmod 700 "${temporary_directory}"
    fi
    entitlements_file="${temporary_directory}/${label// /-}.plist"
    : > "${entitlements_file}"
    chmod 600 "${entitlements_file}"
    if ! codesign -d --entitlements :- "${bundle}" > "${entitlements_file}" 2>/dev/null; then
        fail "unable to read ${label} entitlements from ${bundle}"
    fi
    if ! groups_json=$(plutil -extract \
        'com\.apple\.security\.application-groups' \
        json \
        -o - \
        "${entitlements_file}" 2>/dev/null | tr -d '[:space:]'); then
        fail "${label} entitlements do not declare ${SHARED_APP_GROUP}"
    fi

    [[ "${groups_json}" == "[\"${SHARED_APP_GROUP}\"]" ]] || \
        fail "${label} entitlements must declare exactly ${SHARED_APP_GROUP}"

    if [[ "${label}" == "widget extension" ]]; then
        sandbox_value=$(/usr/libexec/PlistBuddy \
            -c 'Print :com.apple.security.app-sandbox' \
            "${entitlements_file}" 2>/dev/null) || \
            fail "widget extension entitlements must enable com.apple.security.app-sandbox"
        [[ "${sandbox_value}" == true ]] || \
            fail "widget extension entitlements must enable com.apple.security.app-sandbox"

        for forbidden_entitlement in "${FORBIDDEN_WIDGET_ENTITLEMENTS[@]}"; do
            if /usr/libexec/PlistBuddy \
                -c "Print :${forbidden_entitlement}" \
                "${entitlements_file}" >/dev/null 2>&1; then
                fail "widget extension entitlements must not declare ${forbidden_entitlement}"
            fi
        done
    fi
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
    verify_entitlements "${app_bundle}" "app"
    verify_entitlements "${widget_bundle}" "widget extension"
fi

print -- "Verified AgentMeter widget bundle: ${widget_bundle}"
