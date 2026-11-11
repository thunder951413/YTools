#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
NATIVE_DIR="${SCRIPT_DIR:h}"

cd "${NATIVE_DIR}"

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swift_args=(-Xswiftc -warnings-as-errors)
if [[ -n "${YTOOLS_BUILD_PATH:-}" ]]; then
    swift_args+=(--scratch-path "${YTOOLS_BUILD_PATH}")
fi

swift build "${swift_args[@]}"
if xcrun --find xctest >/dev/null 2>&1 || [[ "${CI:-}" == "true" ]]; then
    swift test "${swift_args[@]}"
else
    print "Note: XCTest unavailable under CommandLineTools; skipping swift test (running YToolsCoreChecks)."
fi
swift run "${swift_args[@]}" YToolsCoreChecks
python3 scripts/security_scan.py
python3 scripts/security_scan_test.py

print "Native build, tests, core checks and security scan passed"
