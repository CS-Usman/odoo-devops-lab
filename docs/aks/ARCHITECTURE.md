# Architecture — 2 nodes, prod on Azure, staging on cluster

## Summary

| | Production | Staging |
|---|------------|---------|
| **Odoo web** | **2×** `odoo-prod-web` (PDB `minAvailable: 1`) | **1×** `odoo-staging-web` |
| **Odoo cron** | Cron threads on web (`maxCronThreads`) | Cron disabled on web |
| **Database** | **Azure PostgreSQL Flexible Server** (VNet-private) | **PostgreSQL** StatefulSet on AKS |
| **DB path** | Odoo → **PgBouncer (×2)** → Azure Postgres | Odoo → `postgres-staging` Service |
| **Live filestore** | **Azure File** PVC `odoo-prod-filestore-rwx` (**RWX**, `azurefile-csi`) | **Managed disk** PVC (**RWO**, `managed-csi`) |
| **Blob (backup / refresh)** | `odoo-prod-filestore`, `odoo-backups` containers | `odoo-staging-filestore` after refresh |
| **Public URL** | HTTPS via ingress (e.g. `*.sslip.io`) | HTTPS via ingress (e.g. `staging.*.nip.io`) |

**Only production** uses Azure Postgres. Staging is refreshed by scripts that drop staging data and copy prod DB dump + filestore from Azure/Blob.

**Node pool:** **2 AKS worker nodes** (`aks_node_min_count` = `aks_node_max_count` = 2).

## Platform diagram

```text
INTERNET
   │
   ▼
Azure Load Balancer (134.x.x.x)
   │
   ▼
ingress-nginx + cert-manager (Let's Encrypt TLS)
   ├── https://<ip-dashes>.sslip.io        → Ingress → odoo-prod (8069, /websocket → 8072)
   └── https://staging.<ip>.nip.io         → Ingress → odoo-staging

  Node 1                              Node 2
 ┌──────────────────────────┐      ┌──────────────────────────┐
 │ odoo-prod-web (pod)      │      │ odoo-prod-web (pod)      │
 │ odoo-staging-web         │      │ pgbouncer                │
 │ postgres-staging         │      │ pgbouncer                │
 │ promtail, node-exporter  │      │ promtail, ingress-ready  │
 └───────────┬──────────────┘      └───────────┬──────────────┘
             │                                  │
             │    Azure File RWX (prod filestore) │  shared mount
             ├──────────────────────────────────┤
             │    Azure Blob (backups / sync)   │
             └──────────────┬───────────────────┘
                            ▼
              Azure PostgreSQL (prod only, private)
              Key Vault ← ESO ← pod secrets
```

## Tools & techniques (inventory)

### Cloud & IaC (Terraform)

| Component | Technique |
|-----------|-----------|
| Resource group, VNet, subnets | `azurerm` — AKS + delegated Postgres subnet |
| **AKS** | Managed cluster, Azure CNI, **2-node** pool, workload identity OIDC |
| **PostgreSQL** | Flexible Server, **private** VNet, TLS `require`, lifecycle ignores zone churn |
| **Storage account** | Blob (HNS), containers: backups, prod/staging filestore archives |
| **Key Vault** | RBAC; ESO user-assigned identity + federated credential |
| **IAM** | Kubelet → Blob contributor; ESO → Key Vault Secrets User |

### Kubernetes runtime

| Layer | Tool / pattern |
|-------|----------------|
| Packaging | **Helm** charts: `odoo`, `pgbouncer`, `postgres-staging`, `monitoring/*` |
| GitOps | **Argo CD** Applications on `main` / `staging` branches |
| Ingress | **ingress-nginx** (LoadBalancer), Odoo **Ingress** rules |
| TLS | **cert-manager** + **Let's Encrypt** HTTP-01 (`ClusterIssuer`) |
| Secrets | **External Secrets Operator** + **Azure Key Vault** (fallback: `seed-aks-db-secret.sh`) |
| Prod filestore HA | **Azure File CSI** (`azurefile-csi`), **ReadWriteMany**, migrate: `migrate-prod-filestore-rwx.sh` |
| Staging filestore | **Azure Disk** RWO; refresh from Blob via scripts |
| Pooling | **PgBouncer** Deployment×2, PDB |
| Staging DB | **StatefulSet** + PVC on `managed-csi` |
| Scheduling | Topology spread (web), **PDB** on prod |
| Metrics API | **metrics-server**; addon uses K8s metrics RBAC |

### CI / CD / quality

| Step | Tool |
|------|------|
| Lint / format | **pre-commit**, **Ruff** |
| Secrets scan | **Gitleaks** |
| Image scan | **Trivy** (GHA) |
| Build / registry | **GitHub Actions** → **GHCR** (immutable **SHA** tags) |
| GitOps tags | `helm/odoo/environments/{production,staging}/image-tag.yaml` (bot commits on branch) |
| Branch model | **`main`** = prod Argo; **`staging`** = staging Argo |

### Observability

| Concern | Stack |
|---------|--------|
| Metrics / alerts | **kube-prometheus-stack** (Prometheus, Alertmanager, rules) |
| Dashboards | **Grafana** (+ lab JSON dashboard) |
| Logs | **Loki** + **Promtail**; query `{namespace="odoo"}` |
| Uptime / HTTP | **blackbox-exporter** → `/devops/health` (HTTP/1.0 aware) |
| In-app | **`devops_server_monitor`** Odoo addon |

### App & edge details

| Item | Detail |
|------|--------|
| Odoo version | **17** (custom image + addons in GHCR) |
| Proxy | `proxyMode` + ingress **X-Forwarded-*** |
| Bus / live UI | Ingress paths **`/websocket`** and **`/longpolling` → port 8072** |
| Env separation | Staging **neutralize**; separate secrets (`odoo-db` vs `odoo-staging-db`) |

### Backup & disaster recovery

| Mechanism | Detail |
|-----------|--------|
| **CronJob `odoo-backup`** | On **AKS** (namespace `odoo`), **02:00 UTC**; workload identity → Blob |
| **Terraform** | User-assigned identity `*-backup`, federated SA `odoo-backup`, Blob **Data Contributor** |
| **Blob containers** | `odoo-backups/YYYY-MM-DD/` (dump + tar), `odoo-prod-filestore/filestore.tar.gz` |
| **Azure Postgres** | Private prod DB; platform PITR in portal (optional), lab restore = `restore.sh` |
| **RPO (lab)** | ~24 h (nightly); see [../backup/README.md](../backup/README.md) |
| **RTO (lab)** | ~1–3 h operator-driven (rebuild AKS + optional restore) |

**Operator scripts:** `backup.sh`, `restore.sh`, `restore-staging.sh`, `refresh-staging-from-prod.sh`, `sync-filestore-blob.sh`, `install-backup-cronjob.sh`.

**Out of scope (documented):** multi-region RG loss, backup failure alerts, automated restore drill.

### Scripts (day-0 / day-2)

| Script | Role |
|--------|------|
| `install-backup-cronjob.sh` | Render SA/ConfigMap from Terraform; apply CronJob |
| `install-ingress.sh` / `install-cert-manager.sh` / `install-external-secrets-azure.sh` | Edge & secrets |

**Not in default path (documented optional):** Application Gateway (WAF), HashiCorp Vault, Blob Fuse CSI for live mount.

## Staging refresh flow

```text
1. Scale odoo-staging-web to 0
2. pg_dump Azure Postgres (prod DB)
3. DROP/CREATE odoo_staging on postgres-staging → pg_restore
4. push prod filestore → Blob prod container
5. copy Blob prod → Blob staging
6. pull Blob staging → staging Odoo PVC (RWO)
7. Scale staging Odoo back up (+ neutralize optional)
```

```bash
./scripts/refresh-staging-from-prod.sh
./scripts/restore-staging.sh live
./scripts/restore-staging.sh YYYY-MM-DD
```

## Filestore model (prod vs Blob)

| Tier | Purpose |
|------|---------|
| **Azure File RWX** (`odoo-prod-filestore-rwx`) | **Live** prod attachments — **both** web pods |
| **Azure Blob** | Off-cluster **backup**, staging **refresh** canonical copies |
| **Disk RWO** (staging) | Live staging filestore only |

Migration from disk → Azure File: `./scripts/migrate-prod-filestore-rwx.sh` (one-time before `replicas: 2`).

## Bootstrap order

1. `terraform apply` (AKS, Postgres, Blob, Key Vault, ESO identity)
2. `./scripts/seed-keyvault-secrets.sh` + `./scripts/install-external-secrets-azure.sh`
3. `./scripts/bootstrap-aks.sh` · `./scripts/install-argocd.sh`
4. `kubectl apply -f k8s/argocd/applications/` (apps + monitoring + ingress + cert-manager)
5. `./scripts/install-ingress.sh` · `./scripts/install-cert-manager.sh` (if not only Argo)
6. Argo sync: `postgres-staging` → `pgbouncer` → `odoo-prod` → `odoo-staging` → monitoring → `odoo-backup`
7. `./scripts/install-backup-cronjob.sh` (Terraform outputs for workload identity)

**DR reference:** [../backup/README.md](../backup/README.md).

See [README.md](README.md), [INGRESS.md](INGRESS.md), [../secrets/README.md](../secrets/README.md).
