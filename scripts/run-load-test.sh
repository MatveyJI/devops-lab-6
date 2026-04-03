#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOAD_TEST_URL="${LOAD_TEST_URL:-http://work.127.0.0.1.nip.io/work}"
LOAD_TEST_RPS="${LOAD_TEST_RPS:-220}"
LOAD_TEST_DURATION="${LOAD_TEST_DURATION:-90s}"
LOAD_TEST_INTERVAL="${LOAD_TEST_INTERVAL:-1s}"
LOAD_TEST_TIMEOUT="${LOAD_TEST_TIMEOUT:-30s}"
LOAD_TEST_OUTPUT_DIR="${LOAD_TEST_OUTPUT_DIR:-${ROOT_DIR}/artifacts/load-tests}"
LOAD_TEST_RUN_NAME="${LOAD_TEST_RUN_NAME:-run}"
LOAD_TEST_ALLOW_AB_FALLBACK="${LOAD_TEST_ALLOW_AB_FALLBACK:-true}"

mkdir -p "${LOAD_TEST_OUTPUT_DIR}"
LOG_FILE="${LOAD_TEST_OUTPUT_DIR}/${LOAD_TEST_RUN_NAME}.log"
METRICS_FILE="${LOAD_TEST_OUTPUT_DIR}/${LOAD_TEST_RUN_NAME}.metrics"

if command -v go >/dev/null 2>&1; then
  (
    cd "${ROOT_DIR}/load-tester"
    go run . \
      -url "${LOAD_TEST_URL}" \
      -rps "${LOAD_TEST_RPS}" \
      -duration "${LOAD_TEST_DURATION}" \
      -interval "${LOAD_TEST_INTERVAL}" \
      -timeout "${LOAD_TEST_TIMEOUT}" \
      -success-only=true
  ) | tee "${LOG_FILE}"

  success_rate="$(grep -E 'Процент успешных:' "${LOG_FILE}" | tail -1 | sed -E 's/.*: *([0-9]+([.][0-9]+)?)%.*/\1/')"
  success_rps="$(grep -E 'Успешный RPS:' "${LOG_FILE}" | tail -1 | sed -E 's/.*: *([0-9]+([.][0-9]+)?) req\/s.*/\1/')"

  if [[ -z "${success_rps}" ]]; then
    success_rps="$(grep -E 'Реальный успешный RPS:' "${LOG_FILE}" | tail -1 | sed -E 's/.*: *([0-9]+([.][0-9]+)?) .*/\1/')"
  fi

  if [[ -z "${success_rate}" || -z "${success_rps}" ]]; then
    echo "Failed to parse load test metrics from ${LOG_FILE}" >&2
    exit 1
  fi

  {
    echo "SUCCESS_RATE=${success_rate}"
    echo "SUCCESS_RPS=${success_rps}"
    echo "TARGET_RPS=${LOAD_TEST_RPS}"
    echo "DURATION=${LOAD_TEST_DURATION}"
    echo "URL=${LOAD_TEST_URL}"
  } > "${METRICS_FILE}"

  echo "Saved metrics to ${METRICS_FILE}"
  exit 0
fi

if [[ "${LOAD_TEST_ALLOW_AB_FALLBACK}" != "true" ]]; then
  echo "Go is required for CI load testing, but go binary is not available" >&2
  exit 1
fi

if ! command -v ab >/dev/null 2>&1; then
  echo "Neither go nor ab is available for load testing" >&2
  exit 1
fi

AB_REQUESTS="${AB_REQUESTS:-6000}"
AB_CONCURRENCY="${AB_CONCURRENCY:-700}"

echo "go not found, falling back to ab"
ab -k -n "${AB_REQUESTS}" -c "${AB_CONCURRENCY}" "${LOAD_TEST_URL}" | tee "${LOG_FILE}"
