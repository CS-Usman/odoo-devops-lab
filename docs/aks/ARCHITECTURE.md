# Architecture — 2 VMs, prod on Azure, staging on cluster

## Summary

| | Production | Staging |
|---|------------|---------|
| **Odoo** | `odoo-prod-web` (2+, HPA) + `odoo-prod-cron` | `odoo-staging-web` (1) |
| **Database** | **Azure Database for PostgreSQL** (managed) | **PostgreSQL pod** on AKS (`postgres-staging`, PVC on worker disk) |
| **DB path** | Odoo → **PgBouncer** → Azure Postgres | Odoo → **postgres-staging** Service (no PgBouncer, no Azure) |
| **Filestore** | **Azure Blob** `odoo-prod-filestore` (+ optional Blob Fuse mount) | **Azure Blob** `odoo-staging-filestore` + local PVC after refresh |
| **Refresh** | — | `./scripts/refresh-staging-from-prod.sh` |

**Only production** uses Azure Postgres. Staging is refreshed by scripts that **drop staging data** and copy **prod DB dump + filestore** from Azure/Blob.

**Node pool:** exactly **2 AKS worker VMs** (`aks_node_min_count` = `aks_node_max_count` = 2).

## Diagram (2 VMs, horizontal)

```text
INTERNET ──► Application Gateway ──► odoo.example.com ──► Service odoo-prod-web
                              └──► staging.odoo.example.com ──► Service odoo-staging-web

  VM 1 ◄────────────────────────────────────────────────────────────► VM 2
 ┌─────────────────────────────┐              ┌─────────────────────────────┐
 │ odoo-prod-web  (pods)       │              │ odoo-prod-web  (pods)       │
 │ odoo-prod-cron              │              │ pgbouncer (×2 pods total)     │
 │ odoo-staging-web            │              │ postgres-staging (1 pod)    │
 │                             │              │   └─ PVC: staging Postgres  │
 └─────────────┬───────────────┘              └─────────────┬───────────────┘
               │                                            │
               │         Azure Blob (one storage account)     │
               │    ┌ odoo-prod-filestore (canonical prod)   │
               │    ├ odoo-staging-filestore (after refresh)│
               │    └ odoo-backups (dated dumps)            │
               │                                            │
               └──────────────────┬─────────────────────────┘
                                  ▼
                    Azure PostgreSQL  ← PRODUCTION ONLY
                    database: odoo_devops_lab
                    (private VNet, TLS, PgBouncer pool)
```

## Staging refresh flow

```text
1. Scale odoo-staging-web to 0
2. pg_dump  Azure Postgres (prod DB)
3. DROP/CREATE odoo_staging on postgres-staging pod → pg_restore
4. push prod filestore → Blob prod container
5. copy Blob prod → Blob staging
6. pull Blob staging → staging Odoo PVC
7. Scale staging Odoo back up
```

Commands:

```bash
./scripts/refresh-staging-from-prod.sh   # live copy from Azure prod
./scripts/restore-staging.sh live        # alias
./scripts/restore-staging.sh 2026-08-28  # from dated backup blob only
```

## PgBouncer

- **Production only.** Two replicas, one Service, spread across VM 1 / VM 2 when possible.
- Staging connects directly to `postgres-staging.odoo.svc.cluster.local`.

## Filestore (Blob)

- Terraform: storage account with **HNS**, containers `odoo-prod-filestore`, `odoo-staging-filestore`, `odoo-backups`.
- `./scripts/sync-filestore-blob.sh` — push/pull/copy between pods and containers.
- Production with **multiple web pods** should mount the prod container via **Blob Fuse CSI** (see `k8s/storage/README.md`) or sync on a schedule.

## Bootstrap order

1. `terraform apply`
2. `./scripts/seed-aks-db-secret.sh` (prod + staging secrets + `postgres-staging-auth`)
3. `./scripts/bootstrap-aks.sh`
4. Argo CD: `postgres-staging` → `pgbouncer` → `odoo-prod` → `odoo-staging`

## Is this “production engineering”?

**Yes, as a cost-conscious lab / portfolio pattern** — with clear tradeoffs:

| Good (prod-minded) | Tradeoff |
|--------------------|----------|
| Managed Postgres + TLS + private access for **prod** | Staging DB on a pod is **not** parity with prod (version, extensions, performance differ) |
| PgBouncer, HPA, PDB, GitOps, immutable images | Refresh scripts must be run and tested; staging drift if you forget |
| Blob backups + filestore containers | Blob runtime mount needs CSI or sync discipline for multi-replica Odoo |
| Staging isolated from prod Azure DB | Refresh loads **real prod data** — treat staging URL/secrets as sensitive |

For **enterprise staging**, teams often use a **second managed DB** or anonymized dumps. For **learning and LinkedIn**, this design shows you understand **tiering**: pay for Azure where it matters (prod), keep staging **cheap and disposable** on cluster disk, automate **refresh from prod**.

See [README.md](README.md) for commands.
