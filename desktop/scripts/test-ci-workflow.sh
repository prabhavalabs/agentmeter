#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly REPOSITORY_ROOT="${SCRIPT_DIRECTORY:h:h}"
readonly WORKFLOW="${REPOSITORY_ROOT}/.github/workflows/ci.yml"

[[ -f "${WORKFLOW}" ]] || {
    print -u2 -- "error: CI workflow not found at ${WORKFLOW}"
    exit 1
}

xcode_action=$(awk '
    /xcodebuild -project desktop\/AgentMeter\.xcodeproj/ { capture = 1 }
    capture { print }
    capture && /desktop\/scripts\/verify-widget-bundle\.sh/ { exit }
' "${WORKFLOW}")

[[ "${xcode_action}" == *"CODE_SIGNING_ALLOWED=NO test"* ]] || {
    print -u2 -- "error: CI must run the complete Xcode test action before bundle verification"
    exit 1
}
[[ "${xcode_action}" != *"-only-testing:"* ]] || {
    print -u2 -- "error: CI WidgetKit coverage must not be limited with -only-testing"
    exit 1
}

print -- "Verified CI runs the complete Xcode test action"
