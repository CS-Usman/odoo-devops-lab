# CI/CD — GitHub Actions → GHCR → Azure VM

Push to `main` builds a Docker image, scans it, pushes to GHCR, deploys to the Azure VM, then runs a smoke test.

## Flow

```text
PR / push
  → ci.yml: pre-commit, Gitleaks, Trivy (build only)

push main
  → docker-build.yml: build → Trivy → push GHCR → SSH k3s deploy → smoke test
```

## GitHub secrets

| Secret | Value |
|--------|--------|
| `VM_HOST` | VM public IP |
| `VM_USER` | `azureuser` |
| `VM_SSH_PRIVATE_KEY` | Private key for VM SSH |
| `GHCR_TOKEN` | GitHub PAT with `read:packages` |

## Workflows

| File | When | What |
|------|------|------|
| `.github/workflows/ci.yml` | PR + push | pre-commit, Gitleaks, Trivy |
| `.github/workflows/docker-build.yml` | push `main` | Build, scan, push, k3s deploy, smoke test |

Deploy runs `./scripts/deploy-k8s.sh` (disables Traefik, Helm upgrade, hostPort `:80` / `:8080`).

## VM prerequisites for deploy

k3s and Helm must be installed once on the VM:

```bash
./scripts/install-k3s.sh
./scripts/migrate-compose-to-k8s.sh
./scripts/deploy-k8s.sh
```

After that, every push to `main` rolls out the new image tag (`github.sha`) to both `odoo-prod` and `odoo-staging`.

## Local pre-commit (once)

Requires **Docker running** (hadolint hook uses `hadolint/hadolint` image).

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

Hooks: ruff (our module only), hadolint (docker), gitleaks, XML validation via lxml.

## Smoke test

```bash
VM_HOST=<VM_IP> ./scripts/smoke-test.sh
```

Hits `GET /devops/health` — checks Odoo + DB (`200` + `"status":"ok"`).

Also runs automatically after deploy in GitHub Actions.

## VM one-time setup

See [terraform](../terraform/README.md) and [nginx](../nginx/README.md). Or:

```bash
ansible-playbook -i ansible/inventory ansible/bootstrap.yml
```

## What CI/CD does *not* do

- `terraform apply`
- Vault bootstrap — [vault](../vault/README.md) (one-time on VM)
- Backups — [backup](../backup/README.md)
