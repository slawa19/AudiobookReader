#!/usr/bin/env bash
# Анализатор + тесты. Селектор и опции пробрасываются во `flutter test`:
#   bash scripts/test.sh                                  # всё
#   bash scripts/test.sh test/reader_test.dart            # один файл
#   bash scripts/test.sh test/reader_test.dart --name 'листание'
#   bash scripts/test.sh test/screens_golden_test.dart --update-goldens   # переснять снимки экранов
# Анализатор всегда идёт по всему проекту и должен быть без замечаний (в том числе info).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
require_flutter
cd "${PROJECT_ROOT}"

"${FLUTTER_BIN}" pub get --offline >/dev/null 2>&1 || "${FLUTTER_BIN}" pub get >/dev/null

echo "== flutter analyze"
"${FLUTTER_BIN}" analyze --fatal-infos --fatal-warnings

echo "== flutter test $*"
"${FLUTTER_BIN}" test --reporter compact "$@"
