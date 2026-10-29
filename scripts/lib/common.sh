# shellcheck shell=bash
# Shared helpers for odoo-devops-lab scripts. Source from repo scripts:
#   SCRIPT_DIR=... REPO_DIR=... ; source "${SCRIPT_DIR}/lib/common.sh"

: "${REPO_DIR:?Set REPO_DIR before sourcing common.sh}"

load_env() {
  local env_file="${REPO_DIR}/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  fi
}

require_kubeconfig() {
  : "${KUBECONFIG:?Set KUBECONFIG or run: az aks get-credentials ...}"
}

# Production Postgres is always Azure FQDN — never PgBouncer for pg_dump/pg_restore.
require_azure_prod_postgres() {
  load_env
  if [[ -z "${POSTGRES_FQDN:-}" && -z "${POSTGRES_HOST:-}" ]]; then
    echo "[error] Set POSTGRES_FQDN (or POSTGRES_HOST) to the Azure PostgreSQL private FQDN." >&2
    exit 1
  fi
  export POSTGRES_HOST="${POSTGRES_FQDN:-${POSTGRES_HOST}}"
  export DB_PORT="${DB_PORT:-5432}"
  export PGSSLMODE="${PGSSLMODE:-require}"
}

require_azure_storage() {
  load_env
  : "${AZURE_STORAGE_ACCOUNT:?Set AZURE_STORAGE_ACCOUNT in .env}"
  : "${AZURE_STORAGE_KEY:?Set AZURE_STORAGE_KEY in .env}"
  export AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER:-odoo-backups}"
  export ODOO_PROD_FILESTORE_CONTAINER="${ODOO_PROD_FILESTORE_CONTAINER:-odoo-prod-filestore}"
  export ODOO_STAGING_FILESTORE_CONTAINER="${ODOO_STAGING_FILESTORE_CONTAINER:-odoo-staging-filestore}"
}

odoo_namespace() {
  echo "${ODOO_NAMESPACE:-odoo}"
}

postgres_staging_pod() {
  kubectl -n "$(odoo_namespace)" get pods -l app.kubernetes.io/name=postgres-staging \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

wait_postgres_staging() {
  kubectl -n "$(odoo_namespace)" wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgres-staging --timeout=300s
}
