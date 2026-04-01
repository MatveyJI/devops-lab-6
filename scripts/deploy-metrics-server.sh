#!/usr/bin/env bash
set -euo pipefail

METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-v0.7.2}"
MANIFEST_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

kubectl apply -f "${MANIFEST_URL}"
kubectl -n kube-system patch deployment metrics-server --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment/metrics-server --timeout=240s
