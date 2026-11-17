#!/usr/bin/env bash
# The clickable prototype in the browser.
#   bash scripts/prototype.sh start    # build the web version and serve it at http://127.0.0.1:8642/
#   bash scripts/prototype.sh stop
#   bash scripts/prototype.sh status
# The build does not go online for CanvasKit and fonts (--no-web-resources-cdn, fonts are bundled).
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
    echo "Building the web version…"
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
      echo "The server did not answer 200 (answer: ${code}). Log: ${LOG_FILE}" >&2
      exit 1
    fi
    echo "Prototype: ${URL} (HTTP ${code}, pid $(cat "${PID_FILE}"))"
    ;;
  stop)
    stop
    echo "Stopped."
    ;;
  status)
    if running; then
      echo "Running: ${URL} (HTTP $(http_code), pid $(cat "${PID_FILE}"))"
    else
      echo "Not running."
      exit 3
    fi
    ;;
  *)
    echo "Usage: bash scripts/prototype.sh start|stop|status" >&2
    exit 2
    ;;
esac
