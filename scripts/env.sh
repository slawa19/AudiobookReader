# Общие переменные скриптов. Подключается через `source`, сам не запускается.
#
# Версия Flutter закреплена здесь и только здесь. Источник — официальный список релизов
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
# (проверено 2026-11-14: текущий stable — 3.50.0 от 2026-11-11, Dart 3.14.0).

FLUTTER_VERSION="3.50.0"
FLUTTER_SHA256="6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5"
FLUTTER_ARCHIVE="stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"

# FlutterExtension.kt Flutter 3.50.0: compile/target SDK 36, NDK 28.2.13676358.
# AGP 9.3: https://developer.android.com/build/releases/agp-9-3-0-release-notes
# Архивы и суммы: https://api.adoptium.net/v3/assets/feature_releases/21/ga
# и https://developer.android.com/studio (проверено 2026-11-15).
JDK_VERSION="21.0.13+9"
JDK_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz"
JDK_SHA256="d7f5d5cf865a2902b70ff549b97586a7d3f234e016f041ab447ea740c7d66d1c"
# cmdline-tools 22.0: фиксированный номер архива, суффикс _latest в URL — часть имени Google.
ANDROID_CMDLINE_VERSION="15859902"
ANDROID_CMDLINE_SHA256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
ANDROID_API="36"
ANDROID_BUILD_TOOLS="36.0.0"
ANDROID_NDK="28.2.13676358"
ANDROID_CMAKE="3.22.1"
# У platform-tools нет версионного идентификатора sdkmanager: берём неизменяемый архив.
# SHA-1 опубликована Google в https://dl.google.com/android/repository/repository2-1.xml.
ANDROID_PLATFORM_TOOLS="37.0.3"
ANDROID_PLATFORM_TOOLS_SHA1="e1579b288a7ae4e9bc28dedec6a154d78b3c04ed"

# SDK живёт в домашнем каталоге WSL, а не на /mnt/d: там файловая система в разы медленнее.
SDK_ROOT="${HOME}/sdk"
FLUTTER_HOME="${SDK_ROOT}/flutter-${FLUTTER_VERSION}"
FLUTTER_BIN="${FLUTTER_HOME}/bin/flutter"
export JAVA_HOME="${SDK_ROOT}/jdk-${JDK_VERSION}"
export ANDROID_HOME="${SDK_ROOT}/android"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
SDKMANAGER="${ANDROID_HOME}/cmdline-tools/${ANDROID_CMDLINE_VERSION}/bin/sdkmanager"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Прототип в браузере: фиксированный адрес.
PROTOTYPE_HOST="127.0.0.1"
PROTOTYPE_PORT="8642"

export PATH="${JAVA_HOME}/bin:${FLUTTER_HOME}/bin:${ANDROID_HOME}/platform-tools:${PATH}"
# Flutter не шлёт статистику и не спрашивает об этом.
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true

require_flutter() {
  if [[ ! -x "${FLUTTER_BIN}" || ! -f "${FLUTTER_HOME}/.installed-ok" ]]; then
    echo "Flutter ${FLUTTER_VERSION} не установлен в ${FLUTTER_HOME}. Запустите: bash scripts/setup-wsl.sh" >&2
    exit 2
  fi
}

require_android() {
  if [[ ! -x "${JAVA_HOME}/bin/java" || ! -x "${SDKMANAGER}" \
      || ! -f "${ANDROID_HOME}/platforms/android-${ANDROID_API}/package.xml" \
      || ! -f "${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS}/package.xml" \
      || ! -f "${ANDROID_HOME}/ndk/${ANDROID_NDK}/package.xml" \
      || ! -f "${ANDROID_HOME}/cmake/${ANDROID_CMAKE}/package.xml" ]]; then
    echo "Средства сборки Android не установлены. Запустите: bash scripts/setup-wsl.sh" >&2
    exit 2
  fi
}
