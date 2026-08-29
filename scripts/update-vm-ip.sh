#!/usr/bin/env bash
# Print VM public IP after terraform apply and remind what to update.
# Postgres is private VNet — no public firewall rule to change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")/terraform"

cd "$TF_DIR"

IP="$(terraform output -raw public_ip 2>/dev/null || true)"
FQDN="$(terraform output -raw postgres_fqdn 2>/dev/null || true)"

if [[ -z "$IP" ]]; then
  echo "Run from repo root after: cd terraform && terraform apply" >&2
  exit 1
fi

cat <<EOF
VM public IP:     ${IP}
Postgres FQDN:    ${FQDN}  (private — unchanged when VM IP changes)

Update after IP change:
  1. GitHub → Settings → Secrets → VM_HOST = ${IP}
  2. Browse Odoo at http://${IP}/
  3. See docs/IP-CHANGE.md
EOF
