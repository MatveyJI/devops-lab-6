#!/usr/bin/env bash
set -euo pipefail

INGRESS_VERSION="${INGRESS_VERSION:-controller-v1.11.3}"
MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/kind/deploy.yaml"

kubectl apply -f "${MANIFEST_URL}"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s
