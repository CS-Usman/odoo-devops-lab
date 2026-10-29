#!/usr/bin/env bash
# Kubernetes secrets for prod (PgBouncer → Azure) and staging (in-cluster postgres-staging).
#
#   export POSTGRES_FQDN="$(terraform -chdir=terraform output -raw postgres_fqdn)"
#   export DB_USER=odooadmin DB_PASSWORD='...' STAGING_DB_PASSWORD='...'
#   ./scripts/seed-aks-db-secret.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env

: "${POSTGRES_FQDN:?Azure Postgres FQDN — production only}"
: "${DB_USER:?}"
: "${DB_PASSWORD:?}"
: "${STAGING_DB_PASSWORD:?Password for helm/postgres-staging}"

PROD_DB="${POSTGRES_DB:-odoo_devops_lab}"
STAGING_DB="${STAGING_POSTGRES_DB:-odoo_staging}"
STAGING_USER="${STAGING_DB_USER:-odoo_staging}"
PGBOUNCER_SVC="${PGBOUNCER_HOST:-pgbouncer.odoo.svc.cluster.local}"
STAGING_PG_SVC="${STAGING_PG_HOST:-postgres-staging.odoo.svc.cluster.local}"
NS="$(odoo_namespace)"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic odoo-db \
  --from-literal=DB_HOST="$PGBOUNCER_SVC" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=POSTGRES_HOST="$POSTGRES_FQDN" \
  --from-literal=POSTGRES_DB="$PROD_DB" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic postgres-staging-auth \
  --from-literal=POSTGRES_DB="$STAGING_DB" \
  --from-literal=POSTGRES_USER="$STAGING_USER" \
  --from-literal=POSTGRES_PASSWORD="$STAGING_DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic odoo-staging-db \
  --from-literal=DB_HOST="$STAGING_PG_SVC" \
  --from-literal=DB_USER="$STAGING_USER" \
  --from-literal=DB_PASSWORD="$STAGING_DB_PASSWORD" \
  --from-literal=POSTGRES_DB="$STAGING_DB" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[seed] odoo-db → ${PGBOUNCER_SVC} (backend ${POSTGRES_FQDN})"
echo "[seed] odoo-staging-db → ${STAGING_PG_SVC} (in-cluster, not Azure)"
echo "[seed] Next: ./scripts/bootstrap-aks.sh or ./scripts/deploy-aks-apps.sh"
