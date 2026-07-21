#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
NATIVE_DIR="${SCRIPT_DIR:h}"
APP_NAME="YTools"
APP_DIR="${NATIVE_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${NATIVE_DIR}"
swift build -c release -Xswiftc -warnings-as-errors --product "${APP_NAME}"
BIN_DIR="$(swift build -c release --show-bin-path)"

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
plutil -insert CFBundleShortVersionString -string "0.1.0" "${CONTENTS_DIR}/Info.plist"
plutil -insert CFBundleVersion -string "1" "${CONTENTS_DIR}/Info.plist"
plutil -insert LSMinimumSystemVersion -string "14.0" "${CONTENTS_DIR}/Info.plist"
plutil -insert LSUIElement -bool true "${CONTENTS_DIR}/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "${CONTENTS_DIR}/Info.plist"
plutil -insert NSAppleEventsUsageDescription -string "仅在您确认清空废纸篓时，请求 Finder 执行固定的清空命令。" "${CONTENTS_DIR}/Info.plist"

CODESIGN_IDENTITY="${YTOOLS_CODESIGN_IDENTITY:--}"
CODESIGN_OPTIONS=(--force --sign "${CODESIGN_IDENTITY}" --identifier "com.ztools.native")
if [[ "${CODESIGN_IDENTITY}" != "-" ]]; then
    CODESIGN_OPTIONS+=(--timestamp=none)
fi
codesign "${CODESIGN_OPTIONS[@]}" "${APP_DIR}"
codesign --verify --strict "${APP_DIR}"
plutil -lint "${CONTENTS_DIR}/Info.plist"

print "Built ${APP_DIR}"
