# Phase 8B — GitOps with Argo CD

**Simple idea:** Git says what should run → Argo CD makes k8s match git.

## Install (VM)

```bash
cd ~/odoo-devops-lab && git pull
chmod +x scripts/install-argocd.sh

# Public GitHub repo:
./scripts/install-argocd.sh

# Private repo — needs read-only GitHub PAT:
ARGOCD_GITHUB_TOKEN=ghp_xxx ./scripts/install-argocd.sh
```

## Open Argo UI (laptop)

```bash
ssh -i ~/.ssh/azure_vm_key -L 8081:127.0.0.1:8081 azureuser@<VM_IP> \
  'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n argocd port-forward svc/argocd-server 8081:80'
```

- URL: **http://127.0.0.1:8081**
- User: `admin`
- Password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
```

## First exercise

1. Open **Applications** → **odoo-staging**
2. Status may be **OutOfSync** (normal — git vs cluster differ slightly)
3. Click **Sync** → **Synchronize**
4. Wait for **Healthy** + **Synced**
5. Check staging: `http://<VM_IP>:8080/`

## What we did NOT change yet

- **CI still SSH-deploys** — Argo runs in parallel for learning; later CI only builds image
- **Prod** — still managed by `deploy-k8s.sh` until we add `odoo-prod` Application

## Files

| Path | Purpose |
|------|---------|
| `scripts/install-argocd.sh` | Helm install + staging Application |
| `helm/argocd/values.yaml` | Small Argo CD for 8 GB VM |
| `k8s/argocd/applications/odoo-staging.yaml` | First GitOps app |
