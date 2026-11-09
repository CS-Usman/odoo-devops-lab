data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "lab" {
  name                       = var.key_vault_name
  location                   = azurerm_resource_group.lab.location
  resource_group_name        = azurerm_resource_group.lab.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = true
  tags                       = var.tags
}

# Deploy-time operator (you) can seed secrets from the laptop.
resource "azurerm_role_assignment" "kv_admin_current_user" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name   = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
