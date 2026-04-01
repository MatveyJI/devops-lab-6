#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAFANA_URL="${GRAFANA_URL:-http://grafana.127.0.0.1.nip.io}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin12345}"

wait_for_grafana() {
  local attempts=60
  for _ in $(seq 1 "${attempts}"); do
    if curl -fsS "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "Grafana did not become ready in time" >&2
  return 1
}

post_json() {
  local url="$1"
  local file="$2"

  curl -fsS \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X POST \
    "${url}" \
    --data @"${file}"
}

wait_for_grafana

post_json "${GRAFANA_URL}/api/datasources" "${ROOT_DIR}/monitoring/grafana-datasource.json" || true
post_json "${GRAFANA_URL}/api/dashboards/db" "${ROOT_DIR}/monitoring/grafana-dashboard-work-app-import.json"

echo "Grafana configured:"
echo "  URL: ${GRAFANA_URL}"
echo "  login: ${GRAFANA_USER}"
echo "  password: ${GRAFANA_PASSWORD}"
