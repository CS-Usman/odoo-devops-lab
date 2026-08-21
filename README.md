# odoo-devops-lab

Personal lab for learning DevOps with Odoo 17 — containerize the app, put it on Azure, automate builds and deploys, then add k8s, secrets, and monitoring over time.

## Documentation

Setup and notes for each tool live under **`docs/`**. Start here:

**[docs/README.md](docs/README.md)**

Tool-specific guides (added as we go):

| Topic | README |
|-------|--------|
| Docker & Compose | [docs/docker/README.md](docs/docker/README.md) |

## Repo layout

```
├── addons/              # Odoo custom modules
├── Dockerfile
├── docker-compose.yml
└── docs/                # Per-tool documentation
```

## Roadmap (high level)

1. Local Docker
2. GitHub + Terraform (Azure)
3. CI/CD
4. VM deploy
5. k8s, secrets, observability

For steps, commands, and what we did at each stage — see the README in `docs/` for that tool.
