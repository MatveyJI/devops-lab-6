#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-lab10}"
IMAGE_NAME="${IMAGE_NAME:-work-app:lab4}"

docker build -t "${IMAGE_NAME}" "${ROOT_DIR}"
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"
