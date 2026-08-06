#!/bin/zsh

set -euo pipefail

readonly MINIMUM_XCODEGEN_VERSION="2.45.4"
readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly DESKTOP_ROOT="${SCRIPT_DIRECTORY:h}"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "error: xcodegen ${MINIMUM_XCODEGEN_VERSION} or newer is required"
    exit 1
fi

version_output="$(xcodegen --version 2>&1)" || {
    print -u2 "error: unable to query xcodegen version"
    exit 1
}

version="$(print -r -- "${version_output}" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p')"
if [[ -z "${version}" || "${version}" == *$'\n'* ]]; then
    print -u2 "error: malformed xcodegen version output: ${version_output}"
    exit 1
fi

IFS=. read -r installed_major installed_minor installed_patch <<< "${version}"
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
    print -u2 "error: xcodegen ${version} is too old; ${MINIMUM_XCODEGEN_VERSION} or newer is required"
    exit 1
fi

xcodegen generate --spec "${DESKTOP_ROOT}/project.yml" --project "${DESKTOP_ROOT}"
