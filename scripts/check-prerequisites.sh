#!/usr/bin/env bash
# Quick local checks before terraform apply / bootstrap.

set -euo pipefail

ok=0
fail=0

check() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "[ok] $1 — $("$1" --version 2>/dev/null | head -1 || $1 version 2>/dev/null | head -1 || echo found)"
    ok=$((ok + 1))
  else
    echo "[missing] $1" >&2
    fail=$((fail + 1))
  fi
}

check az
check terraform
check kubectl
check helm
check docker

if az account show >/dev/null 2>&1; then
  echo "[ok] Azure CLI logged in — $(az account show --query name -o tsv)"
else
  echo "[warn] Not logged in — run: az login" >&2
  fail=$((fail + 1))
fi

echo ""
echo "Ready checks: ${ok} ok, ${fail} issues"
exit $(( fail > 0 ? 1 : 0 ))
