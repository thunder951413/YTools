#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
NATIVE_DIR="${SCRIPT_DIR:h}"

cd "${NATIVE_DIR}"

swift_args=(-Xswiftc -warnings-as-errors)
if [[ -n "${YTOOLS_BUILD_PATH:-}" ]]; then
    swift_args+=(--scratch-path "${YTOOLS_BUILD_PATH}")
fi

swift build "${swift_args[@]}"
swift test "${swift_args[@]}"
swift run "${swift_args[@]}" YToolsCoreChecks
python3 scripts/security_scan.py
python3 scripts/security_scan_test.py

print "Native build, tests, core checks and security scan passed"
