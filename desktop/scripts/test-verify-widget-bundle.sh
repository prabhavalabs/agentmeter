#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly DESKTOP_ROOT="${SCRIPT_DIRECTORY:h}"
readonly VERIFIER="${SCRIPT_DIRECTORY}/verify-widget-bundle.sh"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agentmeter-widget-verifier-tests.XXXXXX")"

passed=0

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

on_hup() { exit 129; }
on_int() { exit 130; }
on_term() { exit 143; }

trap cleanup EXIT
trap on_hup HUP
trap on_int INT
trap on_term TERM

fail_test() {
    print -u2 -- "FAIL: $1"
    exit 1
}

pass_test() {
    passed=$(( passed + 1 ))
    print -- "PASS: $1"
}

new_app() {
    local name="$1"
    local app="${TEST_ROOT}/${name}"
    local widget="${app}/Contents/PlugIns/AgentMeterWidgets.appex"

    mkdir -p "${widget}/Contents"
    cp "${DESKTOP_ROOT}/Resources/Info.plist" "${app}/Contents/Info.plist"
    cp "${DESKTOP_ROOT}/Widgets/Resources/Info.plist" "${widget}/Contents/Info.plist"
    /usr/libexec/PlistBuddy \
        -c 'Set :CFBundleExecutable AgentMeterWidgets' \
        -c 'Set :CFBundleIdentifier com.prabhavalabs.agentmeter.desktop.widget' \
        -c 'Set :CFBundleName AgentMeterWidgets' \
        "${widget}/Contents/Info.plist"
    print -r -- "${app}"
}

new_community_app() {
    local name="$1"
    local app="${TEST_ROOT}/${name}"

    mkdir -p "${app}/Contents"
    cp "${DESKTOP_ROOT}/Resources/Info.plist" "${app}/Contents/Info.plist"
    print -r -- "${app}"
}

add_executables() {
    local app="$1"
    local widget="${app}/Contents/PlugIns/AgentMeterWidgets.appex"

    mkdir -p "${app}/Contents/MacOS" "${widget}/Contents/MacOS"
    cp /usr/bin/true "${app}/Contents/MacOS/AgentMeter"
    cp /usr/bin/true "${widget}/Contents/MacOS/AgentMeterWidgets"
}

sign_managed_app() {
    local app="$1"
    local widget_entitlements="$2"
    local app_entitlements="${3:-${DESKTOP_ROOT}/Resources/AgentMeter.entitlements}"
    local widget="${app}/Contents/PlugIns/AgentMeterWidgets.appex"

    add_executables "${app}"
    codesign --force --timestamp=none \
        --entitlements "${widget_entitlements}" \
        --sign - \
        "${widget}" >/dev/null 2>&1
    codesign --force --timestamp=none \
        --entitlements "${app_entitlements}" \
        --sign - \
        "${app}" >/dev/null 2>&1
}

expect_pass() {
    local name="$1"
    shift
    local output="${TEST_ROOT}/result-${passed}.txt"

    "$@" > "${output}" 2>&1 || {
        sed -n '1,40p' "${output}" >&2
        fail_test "${name} unexpectedly failed"
    }
    pass_test "${name}"
}

expect_failure() {
    local name="$1"
    local expected="$2"
    shift 2
    local output="${TEST_ROOT}/result-${passed}.txt"

    if "$@" > "${output}" 2>&1; then
        fail_test "${name} unexpectedly passed"
    fi
    grep -F -- "${expected}" "${output}" >/dev/null || {
        sed -n '1,40p' "${output}" >&2
        fail_test "${name} did not report '${expected}'"
    }
    pass_test "${name}"
}

expect_exit() {
    local name="$1"
    local expected_status="$2"
    shift 2
    local output="${TEST_ROOT}/result-${passed}.txt"
    local result

    set +e
    "$@" > "${output}" 2>&1
    result=$?
    set -e
    [[ "${result}" == "${expected_status}" ]] || {
        sed -n '1,40p' "${output}" >&2
        fail_test "${name} exited ${result}, expected ${expected_status}"
    }
    pass_test "${name}"
}

spaced_app=$(new_app "AgentMeter fixture with spaces.app")
expect_pass "unsigned bundle accepts a spaced path" "${VERIFIER}" "${spaced_app}"

community_app=$(new_community_app "Community fixture.app")
expect_pass "community app has no PlugIns" "${VERIFIER}" --community "${community_app}"
expect_exit "extra positional argument is rejected" 64 \
    "${VERIFIER}" "${spaced_app}" unexpected

wrong_app=$(new_app "Wrong app identifier.app")
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.wrong' \
    "${wrong_app}/Contents/Info.plist"
expect_failure "wrong app identifier is rejected" \
    "unexpected app bundle identifier 'com.example.wrong'" \
    "${VERIFIER}" "${wrong_app}"

wrong_widget=$(new_app "Wrong widget identifier.app")
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.widget' \
    "${wrong_widget}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/Info.plist"
expect_failure "wrong widget identifier is rejected" \
    "unexpected widget bundle identifier 'com.example.widget'" \
    "${VERIFIER}" "${wrong_widget}"

wrong_point=$(new_app "Wrong extension point.app")
/usr/libexec/PlistBuddy -c 'Set :NSExtension:NSExtensionPointIdentifier com.example.extension' \
    "${wrong_point}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/Info.plist"
expect_failure "wrong extension point is rejected" \
    "unexpected widget extension point 'com.example.extension'" \
    "${VERIFIER}" "${wrong_point}"

dangling_community=$(new_community_app "Dangling community PlugIns.app")
ln -s "${TEST_ROOT}/missing-plugins" "${dangling_community}/Contents/PlugIns"
expect_failure "community rejects dangling PlugIns symlink" \
    "community app must not contain" \
    "${VERIFIER}" --community "${dangling_community}"

external_source=$(new_app "External source.app")
external_plugins_host=$(new_community_app "External PlugIns host.app")
ln -s "${external_source}/Contents/PlugIns" "${external_plugins_host}/Contents/PlugIns"
expect_failure "external PlugIns directory is rejected" \
    "PlugIns must be a physical directory inside the app bundle" \
    "${VERIFIER}" "${external_plugins_host}"

external_appex_host=$(new_app "External appex host.app")
rm -rf -- "${external_appex_host}/Contents/PlugIns/AgentMeterWidgets.appex"
ln -s "${external_source}/Contents/PlugIns/AgentMeterWidgets.appex" \
    "${external_appex_host}/Contents/PlugIns/AgentMeterWidgets.appex"
expect_failure "external widget extension is rejected" \
    "widget extension must be a physical directory inside the app bundle" \
    "${VERIFIER}" "${external_appex_host}"

contents_source=$(new_app "External Contents source.app")
contents_host="${TEST_ROOT}/External Contents host.app"
mkdir -p "${contents_host}"
ln -s "${contents_source}/Contents" "${contents_host}/Contents"
expect_failure "external app Contents is rejected" \
    "app Contents must be a physical directory inside the app bundle" \
    "${VERIFIER}" "${contents_host}"

app_plist_host=$(new_app "External app plist host.app")
cp "${app_plist_host}/Contents/Info.plist" "${TEST_ROOT}/external-app-info.plist"
rm -f -- "${app_plist_host}/Contents/Info.plist"
ln -s "${TEST_ROOT}/external-app-info.plist" "${app_plist_host}/Contents/Info.plist"
expect_failure "external app Info.plist is rejected" \
    "app Info.plist must be a physical file inside the app bundle" \
    "${VERIFIER}" "${app_plist_host}"

widget_plist_host=$(new_app "External widget plist host.app")
cp "${widget_plist_host}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/Info.plist" \
    "${TEST_ROOT}/external-widget-info.plist"
rm -f -- "${widget_plist_host}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/Info.plist"
ln -s "${TEST_ROOT}/external-widget-info.plist" \
    "${widget_plist_host}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/Info.plist"
expect_failure "external widget Info.plist is rejected" \
    "widget Info.plist must be a physical file inside the widget extension" \
    "${VERIFIER}" "${widget_plist_host}"

mixed_signature=$(new_app "Mixed signature.app")
add_executables "${mixed_signature}"
codesign --force --timestamp=none \
    --entitlements "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    --sign - \
    "${mixed_signature}/Contents/PlugIns/AgentMeterWidgets.appex" >/dev/null 2>&1
expect_failure "signed widget with unsigned outer app is rejected" \
    "widget extension is signed but outer app is unsigned" \
    "${VERIFIER}" "${mixed_signature}"

opposite_mixed_signature=$(new_app "Opposite mixed signature.app")
add_executables "${opposite_mixed_signature}"
codesign --force --timestamp=none \
    --entitlements "${DESKTOP_ROOT}/Resources/AgentMeter.entitlements" \
    --sign - \
    "${opposite_mixed_signature}" >/dev/null 2>&1
expect_failure "signed outer app with unsigned widget is rejected" \
    "outer app is signed but widget extension is unsigned" \
    "${VERIFIER}" "${opposite_mixed_signature}"

missing_widget_group=$(new_app "Missing widget App Group.app")
add_executables "${missing_widget_group}"
codesign --force --timestamp=none --sign - \
    "${missing_widget_group}/Contents/PlugIns/AgentMeterWidgets.appex" >/dev/null 2>&1
codesign --force --timestamp=none \
    --entitlements "${DESKTOP_ROOT}/Resources/AgentMeter.entitlements" \
    --sign - \
    "${missing_widget_group}" >/dev/null 2>&1
expect_failure "widget without shared App Group is rejected" \
    "widget extension entitlements do not declare group.com.prabhavalabs.agentmeter.shared" \
    "${VERIFIER}" "${missing_widget_group}"

missing_app_group=$(new_app "Missing app App Group.app")
add_executables "${missing_app_group}"
codesign --force --timestamp=none \
    --entitlements "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    --sign - \
    "${missing_app_group}/Contents/PlugIns/AgentMeterWidgets.appex" >/dev/null 2>&1
codesign --force --timestamp=none --sign - "${missing_app_group}" >/dev/null 2>&1
expect_failure "app without shared App Group is rejected" \
    "app entitlements do not declare group.com.prabhavalabs.agentmeter.shared" \
    "${VERIFIER}" "${missing_app_group}"

signed_app=$(new_app "Valid signed bundle.app")
add_executables "${signed_app}"
codesign --force --timestamp=none \
    --entitlements "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    --sign - \
    "${signed_app}/Contents/PlugIns/AgentMeterWidgets.appex" >/dev/null 2>&1
codesign --force --timestamp=none \
    --entitlements "${DESKTOP_ROOT}/Resources/AgentMeter.entitlements" \
    --sign - \
    "${signed_app}" >/dev/null 2>&1
expect_pass "app and widget with shared App Group pass" "${VERIFIER}" "${signed_app}"

missing_sandbox_entitlements="${TEST_ROOT}/missing-sandbox.plist"
cp "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    "${missing_sandbox_entitlements}"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.app-sandbox' \
    "${missing_sandbox_entitlements}"
missing_sandbox_app=$(new_app "Missing widget sandbox.app")
sign_managed_app "${missing_sandbox_app}" "${missing_sandbox_entitlements}"
expect_failure "widget without App Sandbox is rejected" \
    "widget extension entitlements must enable com.apple.security.app-sandbox" \
    "${VERIFIER}" "${missing_sandbox_app}"

disabled_sandbox_entitlements="${TEST_ROOT}/disabled-sandbox.plist"
cp "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    "${disabled_sandbox_entitlements}"
/usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' \
    "${disabled_sandbox_entitlements}"
disabled_sandbox_app=$(new_app "Disabled widget sandbox.app")
sign_managed_app "${disabled_sandbox_app}" "${disabled_sandbox_entitlements}"
expect_failure "widget with disabled App Sandbox is rejected" \
    "widget extension entitlements must enable com.apple.security.app-sandbox" \
    "${VERIFIER}" "${disabled_sandbox_app}"

extra_group_entitlements="${TEST_ROOT}/extra-widget-group.plist"
cp "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    "${extra_group_entitlements}"
/usr/libexec/PlistBuddy \
    -c 'Add :com.apple.security.application-groups:1 string group.example.unexpected' \
    "${extra_group_entitlements}"
extra_group_app=$(new_app "Extra widget App Group.app")
sign_managed_app "${extra_group_app}" "${extra_group_entitlements}"
expect_failure "widget with an extra App Group is rejected" \
    "widget extension entitlements must declare exactly group.com.prabhavalabs.agentmeter.shared" \
    "${VERIFIER}" "${extra_group_app}"

extra_app_group_entitlements="${TEST_ROOT}/extra-app-group.plist"
cp "${DESKTOP_ROOT}/Resources/AgentMeter.entitlements" \
    "${extra_app_group_entitlements}"
/usr/libexec/PlistBuddy \
    -c 'Add :com.apple.security.application-groups:1 string group.example.unexpected' \
    "${extra_app_group_entitlements}"
extra_app_group_app=$(new_app "Extra app App Group.app")
sign_managed_app \
    "${extra_app_group_app}" \
    "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
    "${extra_app_group_entitlements}"
expect_failure "app with an extra App Group is rejected" \
    "app entitlements must declare exactly group.com.prabhavalabs.agentmeter.shared" \
    "${VERIFIER}" "${extra_app_group_app}"

for forbidden_entitlement in \
    com.apple.security.network.client \
    com.apple.security.network.server \
    com.apple.security.device.bluetooth \
    com.apple.security.device.usb \
    com.apple.security.device.camera \
    com.apple.security.device.audio-input \
    com.apple.security.print \
    keychain-access-groups \
    com.apple.security.files.user-selected.read-only \
    com.apple.security.files.user-selected.read-write \
    com.apple.security.files.user-selected.executable \
    com.apple.security.files.downloads.read-only \
    com.apple.security.files.downloads.read-write \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.bookmarks.document-scope \
    com.apple.security.temporary-exception.files.absolute-path.read-only \
    com.apple.security.temporary-exception.files.absolute-path.read-write \
    com.apple.security.temporary-exception.files.home-relative-path.read-only \
    com.apple.security.temporary-exception.files.home-relative-path.read-write \
    com.apple.security.assets.movies.read-only \
    com.apple.security.assets.movies.read-write \
    com.apple.security.assets.music.read-only \
    com.apple.security.assets.music.read-write \
    com.apple.security.assets.pictures.read-only \
    com.apple.security.assets.pictures.read-write
do
    forbidden_entitlements="${TEST_ROOT}/forbidden-${forbidden_entitlement}.plist"
    cp "${DESKTOP_ROOT}/Widgets/Resources/AgentMeterWidget.entitlements" \
        "${forbidden_entitlements}"
    /usr/libexec/PlistBuddy -c "Add :${forbidden_entitlement} bool true" \
        "${forbidden_entitlements}"
    forbidden_app=$(new_app "Forbidden ${forbidden_entitlement}.app")
    sign_managed_app "${forbidden_app}" "${forbidden_entitlements}"
    expect_failure "widget forbidden entitlement ${forbidden_entitlement} is rejected" \
        "widget extension entitlements must not declare ${forbidden_entitlement}" \
        "${VERIFIER}" "${forbidden_app}"
done

interrupt_app=$(new_app "Interrupted entitlement inspection.app")
add_executables "${interrupt_app}"
mkdir -p \
    "${interrupt_app}/Contents/_CodeSignature" \
    "${interrupt_app}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/_CodeSignature" \
    "${TEST_ROOT}/interrupt-bin" \
    "${TEST_ROOT}/interrupt-tmp"
: > "${interrupt_app}/Contents/_CodeSignature/CodeResources"
: > "${interrupt_app}/Contents/PlugIns/AgentMeterWidgets.appex/Contents/_CodeSignature/CodeResources"
print -r -- '#!/bin/zsh
if [[ "$1" == "--verify" ]]; then
    exit 0
fi
if [[ "$1" == "-d" ]]; then
    kill -TERM "$PPID"
    exit 143
fi
exit 1' > "${TEST_ROOT}/interrupt-bin/codesign"
chmod +x "${TEST_ROOT}/interrupt-bin/codesign"
set +e
TMPDIR="${TEST_ROOT}/interrupt-tmp" \
    PATH="${TEST_ROOT}/interrupt-bin:${PATH}" \
    "${VERIFIER}" "${interrupt_app}" > "${TEST_ROOT}/interrupt-result.txt" 2>&1
interrupt_result=$?
set -e
[[ "${interrupt_result}" == 143 ]] || \
    fail_test "interrupted verifier exited ${interrupt_result}, expected 143"
remaining_temporary_files=("${TEST_ROOT}/interrupt-tmp"/agentmeter-widget-entitlements.*(N))
(( ${#remaining_temporary_files} == 0 )) || \
    fail_test "interrupted verifier left entitlement files behind"
pass_test "signal cleanup removes private entitlement files"

print -- "Verifier regression tests passed: ${passed}"
