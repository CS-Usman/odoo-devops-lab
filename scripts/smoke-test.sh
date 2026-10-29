#!/usr/bin/env bash
# HTTP health check for prod and/or staging.
#
#   SMOKE_URL=https://odoo.example.com ./scripts/smoke-test.sh
#   SMOKE_URL=https://staging.odoo.example.com ./scripts/smoke-test.sh
#   SMOKE_URL=https://odoo.example.com STAGING_SMOKE_URL=https://staging... ./scripts/smoke-test.sh

set -euo pipefail

check_url() {
  local base="$1"
  local label="$2"
  local health="${base%/}/devops/health"
  local body_file attempts sleep_secs

  body_file="$(mktemp)"
  attempts="${SMOKE_ATTEMPTS:-30}"
  sleep_secs="${SMOKE_SLEEP:-10}"

  echo "[smoke:${label}] GET ${health}"
  for ((i = 1; i <= attempts; i++)); do
    local code resp
    code="000"
    if curl -sS -o "$body_file" -w '%{http_code}' --max-time 20 "${health}" > /tmp/smoke-http-code 2>/dev/null; then
      code="$(tr -d '\n' < /tmp/smoke-http-code)"
    fi
    resp="$(cat "$body_file" 2>/dev/null || true)"
    if [[ "$code" == "200" ]] && grep -qE '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$resp"; then
      echo "[smoke:${label}] OK"
      rm -f "$body_file"
      return 0
    fi
    echo "[smoke:${label}] attempt ${i}/${attempts} (HTTP ${code})"
    sleep "$sleep_secs"
  done
  rm -f "$body_file"
  echo "[smoke:${label}] FAILED" >&2
  return 1
}

: "${SMOKE_URL:?Set SMOKE_URL (production or single target)}"
FAILED=0
check_url "$SMOKE_URL" prod || FAILED=1

if [[ -n "${STAGING_SMOKE_URL:-}" ]]; then
  check_url "$STAGING_SMOKE_URL" staging || FAILED=1
fi

exit "$FAILED"
