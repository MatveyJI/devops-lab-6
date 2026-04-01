#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-lab10}"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind is required but not installed" >&2
  exit 1
fi

kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT_DIR}/kind/kind-config.yaml"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
