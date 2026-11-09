# External Secrets manifests

| File | Backend |
|------|---------|
| `externalsecret-*-azurekv.yaml` | **Azure Key Vault** (default) — `ClusterSecretStore` `azure-kv-backend` |
| `externalsecret-odoo-*.yaml` (no suffix) | HashiCorp Vault — `vault-backend` |

Apply Azure path:

```bash
./scripts/seed-keyvault-secrets.sh
./scripts/install-external-secrets-azure.sh
```

`cluster-secret-store-azurekv.yaml.tpl` is rendered with Terraform outputs (`key_vault_uri`, ESO service account).

Argo CD: sync `external-secrets-operator` and `odoo-external-secrets` **after** the ClusterSecretStore exists and ESO has workload-identity annotations (use the script once, or mirror the same Helm values in Git).
