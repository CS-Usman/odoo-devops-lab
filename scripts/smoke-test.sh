#!/usr/bin/env bash
# Post-deploy check — Odoo up and DB reachable.
# Usage: VM_HOST=172.198.71.246 ./scripts/smoke-test.sh

set -euo pipefail

: "${VM_HOST:?Set VM_HOST (VM public IP)}"

BASE_URL="http://${VM_HOST}"
HEALTH_URL="${BASE_URL}/devops/health"
MAX_ATTEMPTS="${SMOKE_ATTEMPTS:-30}"
SLEEP_SECS="${SMOKE_SLEEP:-10}"

echo "[smoke] GET ${HEALTH_URL} (up to ${MAX_ATTEMPTS} attempts)"
RESP=""
for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
  if RESP="$(curl -sf "${HEALTH_URL}")"; then
    echo "[smoke] attempt ${i}: OK"
    break
  fi
  echo "[smoke] attempt ${i}/${MAX_ATTEMPTS}: not ready yet"
  if (( i == MAX_ATTEMPTS )); then
    echo "[smoke] FAILED — health check never returned 200" >&2
    curl -sv "${HEALTH_URL}" || true
    exit 1
  fi
  sleep "${SLEEP_SECS}"
done

echo "[smoke] ${RESP}"

echo "${RESP}" | grep -q '"status":"ok"' || {
  echo "[smoke] FAILED — expected status ok" >&2
  exit 1
}

echo "[smoke] OK"
