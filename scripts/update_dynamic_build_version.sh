#!/bin/sh
set -eu

STAMP_DIR="${DERIVED_FILE_DIR}/easysearch_versioning"
HASH_FILE="${STAMP_DIR}/source_hash"
BUILD_FILE="${STAMP_DIR}/build_number"
APP_INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

mkdir -p "${STAMP_DIR}"

collect_version_inputs() {
  find "${SRCROOT}/EasySearch" -type f \( -name "*.swift" -o -name "*.plist" -o -name "*.json" \) -print

  if [ -d "${SRCROOT}/supabase" ]; then
    find "${SRCROOT}/supabase" -type f -print
  fi

  if [ -f "${SRCROOT}/scripts/update_dynamic_build_version.sh" ]; then
    printf '%s\n' "${SRCROOT}/scripts/update_dynamic_build_version.sh"
  fi

  printf '%s\n' "${SRCROOT}/EasySearch.xcodeproj/project.pbxproj"
}

CURRENT_HASH="$(
  collect_version_inputs \
    | LC_ALL=C sort \
    | while IFS= read -r file_path; do
        [ -f "${file_path}" ] || continue
        shasum "${file_path}"
      done \
    | shasum \
    | awk '{ print $1 }'
)"

PREVIOUS_HASH=""
if [ -f "${HASH_FILE}" ]; then
  PREVIOUS_HASH="$(cat "${HASH_FILE}")"
fi

if [ "${CURRENT_HASH}" = "${PREVIOUS_HASH}" ] && [ -f "${BUILD_FILE}" ]; then
  BUILD_VERSION="$(cat "${BUILD_FILE}")"
else
  YEAR="$(date '+%Y')"
  MONTH="$(date '+%m')"
  DAY="$(date '+%d')"
  HOUR="$(date '+%H')"
  MINUTE="$(date '+%M')"

  SEGMENT_TWO=$((10#${MONTH} * 100 + 10#${DAY}))
  SEGMENT_THREE=$((10#${HOUR} * 100 + 10#${MINUTE}))
  BUILD_VERSION="${YEAR}.${SEGMENT_TWO}.${SEGMENT_THREE}"

  printf '%s' "${CURRENT_HASH}" > "${HASH_FILE}"
  printf '%s' "${BUILD_VERSION}" > "${BUILD_FILE}"
fi

if [ ! -f "${APP_INFO_PLIST}" ]; then
  echo "warning: Dynamic versioning skipped because ${APP_INFO_PLIST} does not exist yet."
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "${APP_INFO_PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_VERSION}" "${APP_INFO_PLIST}"

echo "Dynamic build version: ${BUILD_VERSION}"
