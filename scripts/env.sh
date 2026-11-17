# Shared script variables. Included via `source`; never run on its own.
#
# The Flutter version is pinned here and only here. Source: the official release list
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
# (checked 2026-11-14: current stable is 3.50.0 of 2026-11-11, Dart 3.14.0).

FLUTTER_VERSION="3.50.0"
FLUTTER_SHA256="6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5"
FLUTTER_ARCHIVE="stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"

# FlutterExtension.kt Flutter 3.50.0: compile/target SDK 36, NDK 28.2.13676358.
# AGP 9.3: https://developer.android.com/build/releases/agp-9-3-0-release-notes
# Archives and checksums: https://api.adoptium.net/v3/assets/feature_releases/21/ga
# and https://developer.android.com/studio (checked 2026-11-15).
JDK_VERSION="21.0.13+9"
JDK_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz"
JDK_SHA256="d7f5d5cf865a2902b70ff549b97586a7d3f234e016f041ab447ea740c7d66d1c"
# cmdline-tools 22.0: a fixed archive number; the _latest suffix in the URL is part of Google's file name.
ANDROID_CMDLINE_VERSION="15859902"
ANDROID_CMDLINE_SHA256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
ANDROID_API="36"
ANDROID_BUILD_TOOLS="36.0.0"
ANDROID_NDK="28.2.13676358"
ANDROID_CMAKE="3.22.1"
# platform-tools has no versioned sdkmanager identifier, so we take an immutable archive.
# The SHA-1 is published by Google in https://dl.google.com/android/repository/repository2-1.xml.
ANDROID_PLATFORM_TOOLS="37.0.3"
ANDROID_PLATFORM_TOOLS_SHA1="e1579b288a7ae4e9bc28dedec6a154d78b3c04ed"

# The SDK lives in the WSL home directory, not on /mnt/d: that file system is several times slower.
SDK_ROOT="${HOME}/sdk"
FLUTTER_HOME="${SDK_ROOT}/flutter-${FLUTTER_VERSION}"
FLUTTER_BIN="${FLUTTER_HOME}/bin/flutter"
export JAVA_HOME="${SDK_ROOT}/jdk-${JDK_VERSION}"
export ANDROID_HOME="${SDK_ROOT}/android"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
SDKMANAGER="${ANDROID_HOME}/cmdline-tools/${ANDROID_CMDLINE_VERSION}/bin/sdkmanager"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The browser prototype: a fixed address.
PROTOTYPE_HOST="127.0.0.1"
PROTOTYPE_PORT="8642"

export PATH="${JAVA_HOME}/bin:${FLUTTER_HOME}/bin:${ANDROID_HOME}/platform-tools:${PATH}"
# Flutter sends no analytics and does not ask about it.
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true

require_flutter() {
  if [[ ! -x "${FLUTTER_BIN}" || ! -f "${FLUTTER_HOME}/.installed-ok" ]]; then
    echo "Flutter ${FLUTTER_VERSION} is not installed in ${FLUTTER_HOME}. Run: bash scripts/setup-wsl.sh" >&2
    exit 2
  fi
}

require_android() {
  if [[ ! -x "${JAVA_HOME}/bin/java" || ! -x "${SDKMANAGER}" \
      || ! -f "${ANDROID_HOME}/platforms/android-${ANDROID_API}/package.xml" \
      || ! -f "${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS}/package.xml" \
      || ! -f "${ANDROID_HOME}/ndk/${ANDROID_NDK}/package.xml" \
      || ! -f "${ANDROID_HOME}/cmake/${ANDROID_CMAKE}/package.xml" ]]; then
    echo "The Android build tools are not installed. Run: bash scripts/setup-wsl.sh" >&2
    exit 2
  fi
}
