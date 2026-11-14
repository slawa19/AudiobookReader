#!/usr/bin/env bash
# Ставит Flutter SDK закреплённой версии (scripts/env.sh) в ~/sdk и забирает пакеты проекта.
# Повторный запуск ничего не ломает: готовая установка распознаётся по метке и не трогается.
# Android SDK этот скрипт пока не ставит (сборка APK — этап 0 спеки 001).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

missing=()
for tool in curl git tar xz unzip sha256sum; do
  command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
done
if (( ${#missing[@]} > 0 )); then
  echo "Не хватает программ: ${missing[*]}. Поставьте: apt-get install -y curl git xz-utils unzip coreutils" >&2
  exit 1
fi

mkdir -p "${SDK_ROOT}/downloads"

if [[ -f "${FLUTTER_HOME}/.installed-ok" ]]; then
  echo "Flutter ${FLUTTER_VERSION} уже стоит: ${FLUTTER_HOME}"
else
  archive="${SDK_ROOT}/downloads/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  if [[ ! -f "${archive}" ]] || ! echo "${FLUTTER_SHA256}  ${archive}" | sha256sum -c --status; then
    echo "Скачиваю Flutter ${FLUTTER_VERSION}…"
    curl -fL --retry 3 --max-time 1800 -o "${archive}.part" "${FLUTTER_BASE_URL}/${FLUTTER_ARCHIVE}"
    mv -f "${archive}.part" "${archive}"
  fi
  echo "Проверяю контрольную сумму…"
  echo "${FLUTTER_SHA256}  ${archive}" | sha256sum -c -

  tmp="${SDK_ROOT}/.extract-${FLUTTER_VERSION}"
  rm -rf "${tmp}" "${FLUTTER_HOME}"
  mkdir -p "${tmp}"
  echo "Распаковываю…"
  tar -xJf "${archive}" -C "${tmp}"
  mv "${tmp}/flutter" "${FLUTTER_HOME}"
  rm -rf "${tmp}"

  # Архив принадлежит другому владельцу; git внутри SDK иначе отказывается работать.
  git config --global --get-all safe.directory | grep -qx "${FLUTTER_HOME}" \
    || git config --global --add safe.directory "${FLUTTER_HOME}"

  "${FLUTTER_BIN}" --disable-analytics >/dev/null
  "${FLUTTER_HOME}/bin/dart" --disable-analytics >/dev/null || true
  "${FLUTTER_BIN}" config --enable-web >/dev/null
  "${FLUTTER_BIN}" precache --web --no-android --no-ios --no-linux --no-windows --no-macos
  "${FLUTTER_BIN}" --version
  touch "${FLUTTER_HOME}/.installed-ok"
  # Архив больше не нужен: готовая установка распознаётся по метке.
  rm -f "${archive}"
fi

if [[ -f "${PROJECT_ROOT}/pubspec.yaml" ]]; then
  echo "Забираю пакеты проекта…"
  (cd "${PROJECT_ROOT}" && "${FLUTTER_BIN}" pub get)
fi

echo "Готово: ${FLUTTER_BIN}"
