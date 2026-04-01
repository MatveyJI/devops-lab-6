#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v helm >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install helm
  else
    echo "helm is required but not installed" >&2
    exit 1
  fi
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "${ROOT_DIR}/monitoring/kube-prometheus-stack-values.yaml" \
  --wait \
  --timeout 10m

helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --values "${ROOT_DIR}/monitoring/grafana-values.yaml" \
  --wait \
  --timeout 10m

kubectl apply -f "${ROOT_DIR}/k8s/monitoring/service-monitor.yaml"

kubectl rollout status deployment/grafana -n monitoring --timeout=240s

echo "Monitoring URLs:"
echo "  http://prometheus.127.0.0.1.nip.io"
echo "  http://grafana.127.0.0.1.nip.io"
