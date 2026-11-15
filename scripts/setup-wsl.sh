#!/usr/bin/env bash
# Ставит Flutter, JDK и Android SDK закреплённых версий в ~/sdk; работает и в обычном Linux CI.
# Повторный запуск ничего не ломает: готовая установка распознаётся по метке и не трогается.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

missing=()
for tool in curl git tar xz unzip sha256sum sha1sum; do
  command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
done
if (( ${#missing[@]} > 0 )); then
  echo "Не хватает программ: ${missing[*]}. Поставьте: apt-get install -y curl git xz-utils unzip coreutils" >&2
  exit 1
fi

mkdir -p "${SDK_ROOT}/downloads"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "Закреплённые архивы предназначены для Linux x86_64." >&2
  exit 1
fi

# Не оставляем недокачанный архив под именем готового; кэш проверяется перед распаковкой.
download() {
  local url="$1" archive="$2" checksum="$3" algorithm="${4:-sha256sum}"
  if [[ ! -f "${archive}" ]] || ! echo "${checksum}  ${archive}" | "${algorithm}" -c --status; then
    curl -fL --retry 3 --max-time 1800 -o "${archive}.part" "${url}"
    echo "${checksum}  ${archive}.part" | "${algorithm}" -c -
    mv -f "${archive}.part" "${archive}"
  fi
}

if [[ -f "${JAVA_HOME}/.installed-ok" ]]; then
  echo "JDK ${JDK_VERSION} уже стоит: ${JAVA_HOME}"
else
  archive="${SDK_ROOT}/downloads/jdk-${JDK_VERSION}.tar.gz"
  download "${JDK_URL}" "${archive}" "${JDK_SHA256}"
  mkdir -p "${JAVA_HOME}"
  tar -xzf "${archive}" --strip-components=1 -C "${JAVA_HOME}"
  "${JAVA_HOME}/bin/java" -version
  touch "${JAVA_HOME}/.installed-ok"
  rm -f "${archive}"
fi

if [[ -x "${SDKMANAGER}" ]]; then
  echo "Android cmdline-tools ${ANDROID_CMDLINE_VERSION} уже стоят"
else
  archive="${SDK_ROOT}/downloads/commandlinetools-${ANDROID_CMDLINE_VERSION}.zip"
  download "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_VERSION}_latest.zip" \
    "${archive}" "${ANDROID_CMDLINE_SHA256}"
  tmp="${SDK_ROOT}/.extract-cmdline-${ANDROID_CMDLINE_VERSION}"
  rm -rf "${tmp}"
  mkdir -p "${tmp}" "${ANDROID_HOME}/cmdline-tools"
  unzip -q "${archive}" -d "${tmp}"
  mv "${tmp}/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/${ANDROID_CMDLINE_VERSION}"
  rm -rf "${tmp}"
  rm -f "${archive}"
fi

if [[ -f "${ANDROID_HOME}/platform-tools/source.properties" ]] \
    && grep -qx "Pkg.Revision=${ANDROID_PLATFORM_TOOLS}" "${ANDROID_HOME}/platform-tools/source.properties"; then
  echo "Android platform-tools ${ANDROID_PLATFORM_TOOLS} уже стоят"
else
  archive="${SDK_ROOT}/downloads/platform-tools-${ANDROID_PLATFORM_TOOLS}.zip"
  download "https://dl.google.com/android/repository/platform-tools_r${ANDROID_PLATFORM_TOOLS}-linux.zip" \
    "${archive}" "${ANDROID_PLATFORM_TOOLS_SHA1}" sha1sum
  unzip -qo "${archive}" -d "${ANDROID_HOME}"
  rm -f "${archive}"
fi

# yes получает SIGPIPE после завершения sdkmanager: проверяем именно статус sdkmanager.
set +o pipefail
yes | "${SDKMANAGER}" --sdk_root="${ANDROID_HOME}" --licenses >/dev/null
license_status="${PIPESTATUS[1]}"
set -o pipefail
if (( license_status != 0 )); then
  echo "Не удалось принять лицензии Android SDK." >&2
  exit "${license_status}"
fi

packages=()
for package in "platforms;android-${ANDROID_API}" "build-tools;${ANDROID_BUILD_TOOLS}" "ndk;${ANDROID_NDK}"; do
  if [[ ! -f "${ANDROID_HOME}/${package//;/\/}/package.xml" ]]; then
    packages+=("${package}")
  fi
done
if (( ${#packages[@]} > 0 )); then
  "${SDKMANAGER}" --sdk_root="${ANDROID_HOME}" --install "${packages[@]}"
else
  echo "Android SDK ${ANDROID_API}, build-tools ${ANDROID_BUILD_TOOLS}, NDK ${ANDROID_NDK} уже стоят"
fi

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

# Android-артефакты нужны и при уже установленном Flutter; повторный вызов использует кэш.
"${FLUTTER_BIN}" precache --android --no-ios --no-linux --no-windows --no-macos --no-web

if [[ -f "${PROJECT_ROOT}/pubspec.yaml" ]]; then
  echo "Забираю пакеты проекта…"
  (cd "${PROJECT_ROOT}" && "${FLUTTER_BIN}" pub get)
fi

echo "Готово: ${FLUTTER_BIN}"
