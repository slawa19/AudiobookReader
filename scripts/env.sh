# Общие переменные скриптов. Подключается через `source`, сам не запускается.
#
# Версия Flutter закреплена здесь и только здесь. Источник — официальный список релизов
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
# (проверено 2026-11-14: текущий stable — 3.50.0 от 2026-11-11, Dart 3.14.0).

FLUTTER_VERSION="3.50.0"
FLUTTER_SHA256="6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5"
FLUTTER_ARCHIVE="stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"

# SDK живёт в домашнем каталоге WSL, а не на /mnt/d: там файловая система в разы медленнее.
SDK_ROOT="${HOME}/sdk"
FLUTTER_HOME="${SDK_ROOT}/flutter-${FLUTTER_VERSION}"
FLUTTER_BIN="${FLUTTER_HOME}/bin/flutter"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Прототип в браузере: фиксированный адрес.
PROTOTYPE_HOST="127.0.0.1"
PROTOTYPE_PORT="8642"

export PATH="${FLUTTER_HOME}/bin:${PATH}"
# Flutter не шлёт статистику и не спрашивает об этом.
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true

require_flutter() {
  if [[ ! -x "${FLUTTER_BIN}" || ! -f "${FLUTTER_HOME}/.installed-ok" ]]; then
    echo "Flutter ${FLUTTER_VERSION} не установлен в ${FLUTTER_HOME}. Запустите: bash scripts/setup-wsl.sh" >&2
    exit 2
  fi
}
