resource "azurerm_storage_account" "backups" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "backups" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "backups" {
  storage_account_id = azurerm_storage_account.backups.id

  rule {
    name    = "delete-old-backups"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = [""]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention_days
      }
    }
  }
}
