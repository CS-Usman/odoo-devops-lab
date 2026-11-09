# Scheduled backup CronJob → Azure Blob via workload identity.
resource "azurerm_user_assigned_identity" "backup" {
  name                = "${var.aks_cluster_name}-backup"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "backup" {
  name                = "odoo-backup"
  resource_group_name = azurerm_resource_group.lab.name
  parent_id           = azurerm_user_assigned_identity.backup.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.lab.oidc_issuer_url
  subject             = "system:serviceaccount:${var.backup_namespace}:${var.backup_service_account}"
}

resource "azurerm_role_assignment" "backup_blob_contributor" {
  scope                = azurerm_storage_account.backups.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.backup.principal_id
}
