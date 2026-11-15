#!/usr/bin/env bash
# Без флага — release с ключом из .env; --debug — отладочная подпись, в том числе для CI.
# Пароли передаются Gradle только через окружение, без -P и временного key.properties.
set +x
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "${PROJECT_ROOT}"

mode=release
case "${1:-}" in
  --debug) mode=debug ;;
  '') ;;
  *) echo "Использование: bash scripts/build-apk.sh [--debug]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo "Использование: bash scripts/build-apk.sh [--debug]" >&2
  exit 2
fi

if [[ "${mode}" == release ]]; then
  if [[ ! -f .env ]]; then
    echo "Нет .env в корне проекта. Заполните параметры подписи по .env.example." >&2
    exit 2
  fi
  source .env
  set +x
  for name in ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    if [[ -z "${!name:-}" ]]; then
      echo "В .env не задана ${name}. Release-APK без постоянного ключа не собирается." >&2
      exit 2
    fi
    export "${name}"
  done
  if [[ "${ANDROID_KEYSTORE_PATH}" != /* || ! -f "${ANDROID_KEYSTORE_PATH}" ]]; then
    echo "ANDROID_KEYSTORE_PATH должен указывать на существующий файл по абсолютному пути Linux/WSL." >&2
    exit 2
  fi
else
  unset ANDROID_KEYSTORE_PATH ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD
fi

require_flutter
require_android
"${FLUTTER_BIN}" pub get --offline >/dev/null 2>&1 || "${FLUTTER_BIN}" pub get >/dev/null
"${FLUTTER_BIN}" build apk "--${mode}"
echo "APK: ${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-${mode}.apk"
