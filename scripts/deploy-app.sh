#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -k "${ROOT_DIR}/k8s/app"
kubectl rollout status deployment/work-app -n work-app --timeout=240s

echo "Application URLs:"
echo "  http://work.127.0.0.1.nip.io/work"
echo "  http://work.127.0.0.1.nip.io/q/metrics"
