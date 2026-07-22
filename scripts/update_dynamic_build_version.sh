#!/bin/sh
set -eu

APP_INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
STAMP_DIR="${DERIVED_FILE_DIR}/easysearch_versioning"
HASH_FILE="${STAMP_DIR}/source_hash"
BUILD_FILE="${STAMP_DIR}/build_number"
mkdir -p "${STAMP_DIR}"

if git -C "${SRCROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BUILD_VERSION="$(git -C "${SRCROOT}" rev-list --count HEAD)"
  COMMIT_HASH="$(git -C "${SRCROOT}" rev-parse HEAD)"
else
  BUILD_VERSION="${CURRENT_PROJECT_VERSION:-1}"
  COMMIT_HASH="local"
fi

printf '%s' "${COMMIT_HASH}" > "${HASH_FILE}"
printf '%s' "${BUILD_VERSION}" > "${BUILD_FILE}"

if [ ! -f "${APP_INFO_PLIST}" ]; then
  echo "warning: Dynamic versioning skipped because ${APP_INFO_PLIST} does not exist yet."
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "${APP_INFO_PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_VERSION}" "${APP_INFO_PLIST}"

echo "Commit-based build version: ${BUILD_VERSION}"
