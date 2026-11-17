#!/usr/bin/env bash
# Analyzer + tests. The selector and options are passed through to `flutter test`:
#   bash scripts/test.sh                                  # everything
#   bash scripts/test.sh test/reader_test.dart            # one file
#   bash scripts/test.sh test/reader_test.dart --name 'paging'
#   bash scripts/test.sh test/screens_golden_test.dart --update-goldens   # regenerate the screen goldens
# The analyzer always covers the whole project and must report no issues (info included).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
require_flutter
cd "${PROJECT_ROOT}"

"${FLUTTER_BIN}" pub get --offline >/dev/null 2>&1 || "${FLUTTER_BIN}" pub get >/dev/null

echo "== flutter analyze"
"${FLUTTER_BIN}" analyze --fatal-infos --fatal-warnings

echo "== flutter test $*"
"${FLUTTER_BIN}" test --reporter compact "$@"
