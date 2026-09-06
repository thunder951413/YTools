#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
NATIVE_DIR="${SCRIPT_DIR:h}"
APP_NAME="YTools"
APP_VERSION="${YTOOLS_VERSION:-0.2.1}"
APP_DIR="${YTOOLS_DIST_DIR:-${NATIVE_DIR}/dist}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${NATIVE_DIR}"
swift_args=(-c release)
if [[ -n "${YTOOLS_BUILD_PATH:-}" ]]; then
    swift_args+=(--scratch-path "${YTOOLS_BUILD_PATH}")
fi
swift build "${swift_args[@]}" -Xswiftc -warnings-as-errors --product "${APP_NAME}"
BIN_DIR="$(swift build "${swift_args[@]}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${NATIVE_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

plutil -create xml1 "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string "zh_CN" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleDisplayName -string "YTools" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleExecutable -string "${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleIconFile -string "AppIcon" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleIdentifier -string "com.ztools.native" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleName -string "YTools" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundlePackageType -string "APPL" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleShortVersionString -string "${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleVersion -string "${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
plutil -insert LSMinimumSystemVersion -string "14.0" "${CONTENTS_DIR}/Info.plist"
plutil -insert LSUIElement -bool true "${CONTENTS_DIR}/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "${CONTENTS_DIR}/Info.plist"
plutil -insert NSAppleEventsUsageDescription -string "仅在您确认清空废纸篓时，请求 Finder 执行固定的清空命令。" "${CONTENTS_DIR}/Info.plist"

codesign --force --sign - --identifier "com.ztools.native" "${APP_DIR}"
codesign --verify --strict "${APP_DIR}"
plutil -lint "${CONTENTS_DIR}/Info.plist"

print "Built ${APP_DIR}"
