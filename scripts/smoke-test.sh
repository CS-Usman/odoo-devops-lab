#!/usr/bin/env bash
# Post-deploy check — Odoo up and DB reachable (from CI runner → VM public IP).
# Usage: VM_HOST=172.198.71.246 ./scripts/smoke-test.sh

set -euo pipefail

: "${VM_HOST:?Set VM_HOST (VM public IP)}"

BASE_URL="http://${VM_HOST}"
HEALTH_URL="${BASE_URL}/devops/health"
MAX_ATTEMPTS="${SMOKE_ATTEMPTS:-30}"
SLEEP_SECS="${SMOKE_SLEEP:-10}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

health_ok() {
  local body=$1
  grep -qE '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$body"
}

echo "[smoke] GET ${HEALTH_URL} (up to ${MAX_ATTEMPTS} attempts)"
RESP=""
for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
  HTTP_CODE="000"
  if curl -sS -o "$BODY_FILE" -w '%{http_code}' --max-time 20 "${HEALTH_URL}" > /tmp/smoke-http-code 2>/dev/null; then
    HTTP_CODE="$(tr -d '\n' < /tmp/smoke-http-code)"
  fi
  RESP="$(cat "$BODY_FILE" 2>/dev/null || true)"

  if [[ "$HTTP_CODE" == "200" ]] && health_ok "$RESP"; then
    echo "[smoke] attempt ${i}: OK (HTTP 200)"
    break
  fi

  echo "[smoke] attempt ${i}/${MAX_ATTEMPTS}: not ready (HTTP ${HTTP_CODE})"
  if [[ -n "$RESP" ]]; then
    echo "[smoke] body: ${RESP:0:200}"
  fi

  if (( i == MAX_ATTEMPTS )); then
    echo "[smoke] FAILED — health check never returned 200 + status ok" >&2
    echo "[smoke] Hint: HTTP 000 = cannot reach VM — check Azure NSG :80 and GitHub secret VM_HOST" >&2
    curl -sv "${HEALTH_URL}" 2>&1 | tail -20 >&2 || true
    exit 1
  fi
  sleep "${SLEEP_SECS}"
done

echo "[smoke] ${RESP}"
echo "[smoke] OK"
