#!/usr/bin/env bash
# Кликабельный прототип в браузере.
#   bash scripts/prototype.sh start    # собрать веб-версию и поднять на http://127.0.0.1:8642/
#   bash scripts/prototype.sh stop
#   bash scripts/prototype.sh status
# Сборка не ходит в сеть за CanvasKit и шрифтами (--no-web-resources-cdn, шрифты встроены).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "${PROJECT_ROOT}"

RUN_DIR="${PROJECT_ROOT}/.run"
PID_FILE="${RUN_DIR}/prototype.pid"
LOG_FILE="${RUN_DIR}/prototype.log"
URL="http://${PROTOTYPE_HOST}:${PROTOTYPE_PORT}/"

running() {
  [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null
}

http_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${URL}" || true
}

stop() {
  if running; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      running || break
      sleep 0.3
    done
  fi
  rm -f "${PID_FILE}"
}

case "${1:-}" in
  start)
    require_flutter
    mkdir -p "${RUN_DIR}"
    "${FLUTTER_BIN}" pub get >/dev/null
    echo "Собираю веб-версию…"
    "${FLUTTER_BIN}" build web --release --no-web-resources-cdn --no-source-maps
    stop
    nohup setsid python3 -I "${PROJECT_ROOT}/scripts/prototype-server.py" \
      "${PROTOTYPE_HOST}" "${PROTOTYPE_PORT}" "${PROJECT_ROOT}/build/web" >"${LOG_FILE}" 2>&1 < /dev/null &
    echo $! > "${PID_FILE}"
    for _ in $(seq 1 30); do
      [[ "$(http_code)" == "200" ]] && break
      sleep 0.3
    done
    code="$(http_code)"
    if [[ "${code}" != "200" ]]; then
      echo "Сервер не ответил 200 (ответ: ${code}). Лог: ${LOG_FILE}" >&2
      exit 1
    fi
    echo "Прототип: ${URL} (HTTP ${code}, pid $(cat "${PID_FILE}"))"
    ;;
  stop)
    stop
    echo "Остановлен."
    ;;
  status)
    if running; then
      echo "Работает: ${URL} (HTTP $(http_code), pid $(cat "${PID_FILE}"))"
    else
      echo "Не запущен."
      exit 3
    fi
    ;;
  *)
    echo "Использование: bash scripts/prototype.sh start|stop|status" >&2
    exit 2
    ;;
esac
