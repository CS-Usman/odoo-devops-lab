# CI/CD — GitHub Actions → GHCR → Azure VM

Push to `main` builds a Docker image, scans it, pushes to GHCR, deploys to the Azure VM, then runs a smoke test.

## Flow

```text
PR / push
  → ci.yml: pre-commit, Gitleaks, Trivy (build only)

push main
  → docker-build.yml: build → Trivy → push GHCR → SSH deploy → smoke test
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
| `.github/workflows/docker-build.yml` | push `main` | Build, scan, push, deploy, smoke test |

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
- VM `.env` secrets
- Backups — [backup](../backup/README.md)
