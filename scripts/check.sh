#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
NATIVE_DIR="${SCRIPT_DIR:h}"

cd "${NATIVE_DIR}"
swift build -Xswiftc -warnings-as-errors
swift run -Xswiftc -warnings-as-errors YToolsCoreChecks

if command -v rg >/dev/null 2>&1; then
    if rg -n \
        --glob '*.swift' \
        '(URLSession|NWConnection|WKWebView|WebKit|http://|https://|dlopen|NSAppleScript|/bin/(sh|bash|zsh))' \
        Sources/YTools Sources/YToolsCore Sources/YToolsModuleKit; then
        print -u2 "Forbidden network, web, dynamic-code or shell API found in runtime sources"
        exit 1
    fi
fi

print "Native build and core checks passed"
