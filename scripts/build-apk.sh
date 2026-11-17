#!/usr/bin/env bash
# No flag: release build signed with the key from the environment or .env; --debug: debug signing;
# --fake: a separate fake build.
# Passwords reach Gradle only through the environment, with no -P and no temporary key.properties.
set +x
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "${PROJECT_ROOT}"

mode=release
fake=false
for arg in "$@"; do
  case "${arg}" in
    --debug) mode=debug ;;
    --fake) fake=true ;;
    *) echo "Usage: bash scripts/build-apk.sh [--debug] [--fake]" >&2; exit 2 ;;
  esac
done

if [[ "${mode}" == release ]]; then
  # CI passes the four signing variables through the environment; locally they come from .env.
  key_vars=(ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD)
  in_environment=true
  for name in "${key_vars[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      in_environment=false
    fi
  done
  if [[ "${in_environment}" == false ]]; then
    if [[ ! -f .env ]]; then
      echo "No .env in the project root. Fill in the signing parameters following .env.example." >&2
      exit 2
    fi
    source .env
    set +x
  fi
  for name in "${key_vars[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      echo "${name} is not set (environment or .env). A release APK is not built without the permanent key." >&2
      exit 2
    fi
    export "${name}"
  done
  if [[ "${ANDROID_KEYSTORE_PATH}" != /* || ! -f "${ANDROID_KEYSTORE_PATH}" ]]; then
    echo "ANDROID_KEYSTORE_PATH must point to an existing file by an absolute Linux/WSL path." >&2
    exit 2
  fi
else
  unset ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD
fi

require_flutter
require_android
# --enforce-lockfile: the resolved versions must match pubspec.lock exactly, so a build never picks up newer packages.
"${FLUTTER_BIN}" pub get --offline --enforce-lockfile >/dev/null 2>&1 \
  || "${FLUTTER_BIN}" pub get --enforce-lockfile >/dev/null
# One parameter selects both the Dart flag and the applicationId/name in Gradle.
"${FLUTTER_BIN}" build apk "--${mode}" "--dart-define=FAKE_TTS=${fake}"
apk="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-${mode}.apk"
variant=real
if [[ "${fake}" == true ]]; then
  variant=fake
fi
# Flutter writes both variants to app-${mode}.apk; copies named after the variant keep both results.
variant_apk="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-${variant}-${mode}.apk"
cp "${apk}" "${variant_apk}"
apk="${variant_apk}"
echo "APK: ${apk}"
