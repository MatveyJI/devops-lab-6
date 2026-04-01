#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/scripts/create-kind-cluster.sh"
"${ROOT_DIR}/scripts/deploy-ingress-nginx.sh"
"${ROOT_DIR}/scripts/deploy-metrics-server.sh"
"${ROOT_DIR}/scripts/build-and-load-image.sh"
"${ROOT_DIR}/scripts/deploy-app.sh"
"${ROOT_DIR}/scripts/install-monitoring.sh"
"${ROOT_DIR}/scripts/configure-grafana.sh"

echo
echo "Lab environment is ready."
echo "App:        http://work.127.0.0.1.nip.io/work"
echo "Metrics:    http://work.127.0.0.1.nip.io/q/metrics"
echo "Prometheus: http://prometheus.127.0.0.1.nip.io"
echo "Grafana:    http://grafana.127.0.0.1.nip.io"
echo
echo "Run load test with:"
echo "  ${ROOT_DIR}/scripts/run-load-test.sh"
