# Ingress (nginx + public LoadBalancer)

## What this fixes

Odoo Services stay **ClusterIP** inside the cluster. **ingress-nginx** gets an **Azure LoadBalancer IP** and routes HTTP from the internet to `odoo-prod` / `odoo-staging`.

```text
Internet → Azure LB → ingress-nginx → TLS (cert-manager) → Ingress
  /  → odoo-prod-web:8069
  /websocket, /longpolling → odoo-prod-web:8072   (Odoo 17 bus)
```

Application Gateway in older docs is optional (WAF, certificates at edge). This lab’s **default path** is **ingress-nginx** (GitOps: `k8s/argocd/applications/ingress-nginx.yaml`).

## Bootstrap

```bash
# Option A — GitOps (after Argo CD)
kubectl apply -f k8s/argocd/applications/ingress-nginx.yaml

# Option B — script (no Argo)
./scripts/install-ingress.sh
```

Wait for an external IP, then set hosts (see script output). **Lab DNS:** `52-14-0-26.sslip.io` resolves to `52.14.0.26` — no domain purchase.

## Enable Odoo routes

Edit and push:

| File | Purpose |
|------|---------|
| `helm/odoo/environments/production/ingress.yaml` | `ingress.enabled: true`, `host: <prod-host>` |
| `helm/odoo/environments/staging/ingress.yaml` | staging host (different hostname on same LB) |

Argo CD apps already include these value files on `main` / `staging`.

## TLS (Let's Encrypt)

```bash
export LETSENCRYPT_EMAIL='you@example.com'
./scripts/install-cert-manager.sh
# or: kubectl apply -f k8s/argocd/applications/cert-manager.yaml (then apply ClusterIssuer via script)
```

Helm: `ingress.certManager.clusterIssuer: letsencrypt-prod` + `ingress.tls.enabled: true` in `environments/production/ingress.yaml`.

Cert-manager creates secret `odoo-prod-tls`; nginx redirects HTTP → HTTPS.

| Env | Public URL |
|-----|------------|
| Prod | `https://134-33-199-248.sslip.io` |
| Staging | `https://staging.<LB-IP-dots>.nip.io` (e.g. `https://staging.134.33.199.248.nip.io`) |

`staging-…-sslip.io` is **not** a valid sslip.io pattern — nginx returns **404** without an Ingress rule.

Smoke test:

```bash
SMOKE_URL=https://134-33-199-248.sslip.io ./scripts/smoke-test.sh
STAGING_SMOKE_URL=https://staging.134.33.199.248.nip.io ./scripts/smoke-test.sh
```

Alternative: terminate TLS at Application Gateway (not default in this lab).

## Odoo proxy mode

Helm sets `proxyMode: true` so Odoo trusts `X-Forwarded-*` headers from nginx.

## Verify

```bash
kubectl -n odoo get ingress
kubectl -n cert-manager get clusterissuer
kubectl -n odoo get certificate
curl -I "https://<prod-host>/web/login"
```
