# Read-only access to Odoo lab secrets (KV v2 mount: secret/).
# Used by External Secrets Operator and backup jobs via Vault K8s auth.

path "secret/data/odoo/*" {
  capabilities = ["read"]
}

path "secret/metadata/odoo/*" {
  capabilities = ["read", "list"]
}
