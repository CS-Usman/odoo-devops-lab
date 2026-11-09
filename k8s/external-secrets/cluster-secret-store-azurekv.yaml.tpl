apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-kv-backend
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "${KEY_VAULT_URI}"
      serviceAccountRef:
        name: ${ESO_SERVICE_ACCOUNT}
        namespace: ${ESO_NAMESPACE}
