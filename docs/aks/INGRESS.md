# Ingress (nginx + public LoadBalancer)

## What this fixes

Odoo Services stay **ClusterIP** inside the cluster. **ingress-nginx** gets an **Azure LoadBalancer IP** and routes HTTP from the internet to `odoo-prod` / `odoo-staging`.

```text
Internet → Azure LB → ingress-nginx → Ingress → odoo-prod-web:8069 (+ /longpolling → 8072)
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

## TLS (optional)

1. Install [cert-manager](https://cert-manager.io/) and a `ClusterIssuer` (Let’s Encrypt), or
2. Terminate TLS at a future Application Gateway.

Until then, use `http://` for smoke tests or self-signed secrets in `ingress.tls`.

## Odoo proxy mode

Helm sets `proxyMode: true` so Odoo trusts `X-Forwarded-*` headers from nginx.

## Verify

```bash
SMOKE_URL=http://<your-host> ./scripts/smoke-test.sh
kubectl -n odoo get ingress
```
