#!/usr/bin/env bash
# Без флага — release с ключом из .env; --debug — отладочная подпись, --fake — отдельная подставная сборка.
# Пароли передаются Gradle только через окружение, без -P и временного key.properties.
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
    *) echo "Использование: bash scripts/build-apk.sh [--debug] [--fake]" >&2; exit 2 ;;
  esac
done

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
# Один параметр выбирает и Dart-признак, и applicationId/название в Gradle.
"${FLUTTER_BIN}" build apk "--${mode}" "--dart-define=FAKE_TTS=${fake}"
apk="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-${mode}.apk"
variant=real
if [[ "${fake}" == true ]]; then
  variant=fake
fi
# Flutter пишет оба варианта в app-${mode}.apk; копии с именем варианта сохраняют оба результата.
variant_apk="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-${variant}-${mode}.apk"
cp "${apk}" "${variant_apk}"
apk="${variant_apk}"
echo "APK: ${apk}"
