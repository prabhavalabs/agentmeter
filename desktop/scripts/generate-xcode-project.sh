#!/bin/zsh

set -euo pipefail

readonly MINIMUM_XCODEGEN_VERSION="2.45.4"
readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly DESKTOP_ROOT="${SCRIPT_DIRECTORY:h}"
readonly XCODEGEN_COMMAND="${XCODEGEN_BIN:-xcodegen}"
readonly XCODEGEN_VERSION_PATTERN='^Version: ([0-9]+)\.([0-9]+)\.([0-9]+)$'

if ! command -v "${XCODEGEN_COMMAND}" >/dev/null 2>&1; then
    print -u2 "error: xcodegen ${MINIMUM_XCODEGEN_VERSION} or newer is required"
    exit 1
fi

version_output="$("${XCODEGEN_COMMAND}" --version 2>&1)" || {
    print -u2 "error: unable to query xcodegen version"
    exit 1
}

if [[ ! "${version_output}" =~ ${XCODEGEN_VERSION_PATTERN} ]]; then
    print -u2 "error: malformed xcodegen version output: ${version_output}"
    exit 1
fi

installed_major="${match[1]}"
installed_minor="${match[2]}"
installed_patch="${match[3]}"
IFS=. read -r required_major required_minor required_patch <<< "${MINIMUM_XCODEGEN_VERSION}"

installed_major=$(( 10#${installed_major} ))
installed_minor=$(( 10#${installed_minor} ))
installed_patch=$(( 10#${installed_patch} ))
required_major=$(( 10#${required_major} ))
required_minor=$(( 10#${required_minor} ))
required_patch=$(( 10#${required_patch} ))

if (( installed_major < required_major
    || (installed_major == required_major && installed_minor < required_minor)
    || (installed_major == required_major && installed_minor == required_minor
        && installed_patch < required_patch) )); then
    print -u2 "error: xcodegen ${version_output#Version: } is too old; ${MINIMUM_XCODEGEN_VERSION} or newer is required"
    exit 1
fi

"${XCODEGEN_COMMAND}" generate --spec "${DESKTOP_ROOT}/project.yml" --project "${DESKTOP_ROOT}"
