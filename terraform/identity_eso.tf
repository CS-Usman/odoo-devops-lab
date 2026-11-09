# External Secrets Operator → Azure Key Vault via workload identity.
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.aks_cluster_name}-eso"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "eso" {
  name                = "external-secrets"
  resource_group_name = azurerm_resource_group.lab.name
  parent_id           = azurerm_user_assigned_identity.eso.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.lab.oidc_issuer_url
  subject             = "system:serviceaccount:${var.eso_namespace}:${var.eso_service_account}"
}

resource "azurerm_role_assignment" "eso_kv_secrets_user" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso.principal_id
}
