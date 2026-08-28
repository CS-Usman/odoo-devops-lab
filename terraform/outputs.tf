output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "public_ip" {
  description = "SSH and Odoo URL: http://<this-ip>:8069"
  value       = azurerm_public_ip.lab.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.lab.ip_address}"
}

output "postgres_fqdn" {
  description = "Private FQDN — reachable from the VM inside the VNet"
  value       = azurerm_postgresql_flexible_server.lab.fqdn
}

output "postgres_database_name" {
  value = azurerm_postgresql_flexible_server_database.odoo.name
}

output "postgres_admin_login" {
  value = var.postgres_admin_login
}

output "storage_account_name" {
  description = "Azure Blob storage account for backups"
  value       = azurerm_storage_account.backups.name
}

output "storage_container_name" {
  value = azurerm_storage_container.backups.name
}

output "storage_blob_endpoint" {
  value = azurerm_storage_account.backups.primary_blob_endpoint
}

output "storage_primary_access_key" {
  description = "Copy to VM .env as AZURE_STORAGE_KEY — do not commit"
  value       = azurerm_storage_account.backups.primary_access_key
  sensitive   = true
}
