output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.lab.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.lab.oidc_issuer_url
}

output "aks_get_credentials_command" {
  value = "az aks get-credentials -g ${azurerm_resource_group.lab.name} -n ${azurerm_kubernetes_cluster.lab.name} --overwrite-existing"
}

output "postgres_fqdn" {
  description = "Private FQDN — production only; reachable from AKS inside the VNet"
  value       = azurerm_postgresql_flexible_server.lab.fqdn
}

output "postgres_database_name" {
  value = azurerm_postgresql_flexible_server_database.odoo.name
}

output "postgres_admin_login" {
  value = var.postgres_admin_login
}

output "storage_account_name" {
  description = "Azure Blob — backups + Odoo filestore containers"
  value       = azurerm_storage_account.backups.name
}

output "storage_container_name" {
  value = azurerm_storage_container.backups.name
}

output "odoo_prod_filestore_container_name" {
  value = azurerm_storage_container.odoo_prod_filestore.name
}

output "odoo_staging_filestore_container_name" {
  value = azurerm_storage_container.odoo_staging_filestore.name
}

output "storage_blob_endpoint" {
  value = azurerm_storage_account.backups.primary_blob_endpoint
}
