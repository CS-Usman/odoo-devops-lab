#!/usr/bin/env bash
# Mark staging Odoo DB as neutralized (no outbound mail, etc.) — Odoo built-in command.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
NS="$(odoo_namespace)"
DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"
echo "[neutralize] deployment=odoo-staging-web db=${DB}"
kubectl -n "$NS" exec deploy/odoo-staging-web -- sh -c \
  "odoo neutralize -c /etc/odoo/config/odoo.conf -d ${DB} \
  --db_host=\"\$HOST\" --db_user=\"\$USER\" --db_password=\"\$PASSWORD\" --stop-after-init"
echo "[neutralize] Done (database.is_neutralized in ir_config_parameter)."
