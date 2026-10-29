# CI/CD

## Pipelines

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `.github/workflows/ci.yml` | PR + push `main` | pre-commit, Gitleaks, Trivy image build |
| `.github/workflows/docker-build.yml` | push `main` | Build, scan, push **GHCR**, bump GitOps image tag |

## Production deploy flow (GitOps)

```text
git push main
  → GitHub Actions builds ghcr.io/cs-usman/odoo-devops-lab:<sha>
  → commits helm/odoo/environments/production/image-tag.yaml
  → Argo CD syncs odoo-prod + pgbouncer Applications
```

No SSH deploy. Cluster changes come from git + Argo CD.

## Local checks

```bash
pre-commit install
pre-commit run --all-files
docker compose up -d --build
```

## Secrets (GitHub)

| Secret | Use |
|--------|-----|
| `GITHUB_TOKEN` | Built-in — push to GHCR and GitOps commit |
| `GHCR_TOKEN` | Optional pull secret on cluster if repo is private |

## Smoke test

After ingress is configured:

```bash
export SMOKE_URL=https://odoo.example.com
./scripts/smoke-test.sh
```

Until DNS/App Gateway exist, use port-forward to the Odoo Service.
