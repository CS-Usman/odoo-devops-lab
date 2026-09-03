#!/usr/bin/env bash
# Deploy prod + staging Odoo on k3s via Helm.
# Prod DB = Azure Postgres. Staging DB = postgres:16 pod on VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_DIR}/.env"
CHART="${REPO_DIR}/helm/odoo"

export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-/opt/vault/tls/tls.crt}"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if ! command -v helm >/dev/null; then
  echo "helm not found — run ./scripts/install-k3s.sh first (installs Helm too)" >&2
  exit 1
fi

"${SCRIPT_DIR}/disable-traefik.sh"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

wait_eso_secret() {
  local name=$1
  local deadline=$((SECONDS + 180))
  echo "[k8s] Wait for ExternalSecret ${name}..."
  until kubectl -n odoo get secret "$name" >/dev/null 2>&1 \
    && kubectl -n odoo get externalsecret "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; do
    if (( SECONDS >= deadline )); then
      echo "[k8s] Timed out waiting for ExternalSecret ${name}" >&2
      echo "[k8s] Run: ./scripts/vault-seed-secrets.sh && ./scripts/install-external-secrets.sh" >&2
      kubectl -n odoo describe externalsecret "$name" 2>&1 | tail -15 >&2 || true
      return 1
    fi
    sleep 5
  done
}

echo "[k8s] Namespace..."
kubectl create namespace odoo --dry-run=client -o yaml | kubectl apply -f -

echo "[k8s] Vault-backed secrets (External Secrets Operator)..."
if vault status >/dev/null 2>&1 && ! vault status -format=json 2>/dev/null | grep -q '"sealed":true'; then
  echo "[k8s] Ensure staging keys in Vault (DB_HOST, POSTGRES_DB)..."
  vault kv patch secret/odoo/staging \
    DB_HOST=postgres-staging \
    POSTGRES_DB=odoo_staging 2>/dev/null || true
fi
for sec in odoo-db odoo-staging-db postgres-staging; do
  wait_eso_secret "$sec"
done

echo "[k8s] Staging Postgres (on VM, not Azure)..."
kubectl apply -f "${REPO_DIR}/k8s/postgres-staging.yaml"
kubectl -n odoo wait --for=condition=Available deployment/postgres-staging --timeout=180s

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  kubectl -n odoo create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username=CS-Usman \
    --docker-password="$GHCR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

HELM_EXTRA=()
if kubectl -n odoo get secret ghcr-pull >/dev/null 2>&1; then
  HELM_EXTRA=(-f "${CHART}/values-ghcr-pull.yaml")
fi

IMAGE_TAG="${IMAGE_TAG:-latest}"
HELM_SET=(--set "image.tag=${IMAGE_TAG}")

DOCKER_GID="$(getent group docker | cut -d: -f3 || true)"
if [[ -n "$DOCKER_GID" ]]; then
  HELM_SET+=(--set "dockerSocket.gid=${DOCKER_GID}")
  echo "[k8s] Docker socket supplementalGroup: ${DOCKER_GID}"
fi

echo "[k8s] Image tag: ${IMAGE_TAG}"

# Legacy routing CRs — Odoo uses hostPort now.
kubectl -n odoo delete ingress odoo-prod odoo-staging --ignore-not-found 2>/dev/null || true
kubectl -n odoo delete ingressroute odoo-prod odoo-staging --ignore-not-found 2>/dev/null || true

# Compose is retired after k3s cutover — keep it stopped if present.
if [[ -f "${REPO_DIR}/docker-compose.azure.yml" ]]; then
  sudo docker compose -f "${REPO_DIR}/docker-compose.azure.yml" stop 2>/dev/null || true
fi

echo "[k8s] Helm odoo-prod (Azure DB)..."
helm upgrade --install odoo-prod "$CHART" \
  -n odoo \
  -f "${CHART}/values-prod.yaml" \
  "${HELM_EXTRA[@]}" \
  "${HELM_SET[@]}"

echo "[k8s] Helm odoo-staging (VM postgres)..."
helm upgrade --install odoo-staging "$CHART" \
  -n odoo \
  -f "${CHART}/values-staging.yaml" \
  "${HELM_EXTRA[@]}" \
  "${HELM_SET[@]}"

rollout_wait() {
  local dep=$1
  if ! kubectl -n odoo rollout status "deployment/${dep}" --timeout=600s; then
    echo "[k8s] ${dep} rollout failed — diagnostics:" >&2
    kubectl -n odoo get pods -l "app.kubernetes.io/name=${dep}" -o wide >&2 || true
    kubectl -n odoo describe pod -l "app.kubernetes.io/name=${dep}" 2>&1 | tail -50 >&2 || true
    return 1
  fi
}

rollout_wait odoo-prod
rollout_wait odoo-staging
kubectl -n odoo get pods,svc

echo "[k8s] Configure host Nginx (:80 → :8069)..."
"${SCRIPT_DIR}/setup-nginx-k8s.sh"

echo "[k8s] Wait for prod health on http://127.0.0.1/devops/health ..."
health_deadline=$((SECONDS + 420))
until curl -sf --max-time 15 http://127.0.0.1/devops/health | grep -qE '"status"[[:space:]]*:[[:space:]]*"ok"'; do
  if (( SECONDS >= health_deadline )); then
    echo "[k8s] FAILED — prod health not OK after 7 minutes" >&2
    kubectl -n odoo get pods -o wide >&2 || true
    curl -sv http://127.0.0.1/devops/health 2>&1 | tail -15 >&2 || true
    curl -sv http://127.0.0.1:8069/devops/health 2>&1 | tail -10 >&2 || true
    systemctl is-active nginx >&2 || true
    exit 1
  fi
  echo "[k8s] Odoo still starting..."
  sleep 10
done
echo "[k8s] Prod health OK on :80"

PUBLIC_IP="$(curl -sf ifconfig.me 2>/dev/null || true)"
if [[ -n "$PUBLIC_IP" ]]; then
  echo "[k8s] Check public IP http://${PUBLIC_IP}/devops/health ..."
  if curl -sf --max-time 15 "http://${PUBLIC_IP}/devops/health" | grep -qE '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    echo "[k8s] Public IP health OK"
  else
    echo "[k8s] WARNING: localhost OK but public IP failed — Azure NSG :80 or wrong VM_HOST in GitHub?" >&2
    echo "[k8s]   terraform output public_ip  →  update GitHub secret VM_HOST" >&2
    ss -tlnp | grep ':80' >&2 || true
  fi
fi

echo ""
echo "Prod:    http://$(curl -sf ifconfig.me 2>/dev/null || echo '<VM_IP>')/  → Azure Postgres"
echo "Staging: http://$(curl -sf ifconfig.me 2>/dev/null || echo '<VM_IP>'):8080/ → VM postgres-staging pod"
echo "Run ./scripts/seed-staging.sh once to copy prod data into staging."
