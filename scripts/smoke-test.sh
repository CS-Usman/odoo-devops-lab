#!/usr/bin/env bash
# Post-deploy check — Odoo up and DB reachable.
# Usage: VM_HOST=172.198.71.246 ./scripts/smoke-test.sh

set -euo pipefail

: "${VM_HOST:?Set VM_HOST (VM public IP)}"

BASE_URL="http://${VM_HOST}"
HEALTH_URL="${BASE_URL}/devops/health"

echo "[smoke] GET ${HEALTH_URL}"
RESP="$(curl -sf "${HEALTH_URL}")"
echo "[smoke] ${RESP}"

echo "${RESP}" | grep -q '"status":"ok"' || {
  echo "[smoke] FAILED — expected status ok" >&2
  exit 1
}

echo "[smoke] OK"
