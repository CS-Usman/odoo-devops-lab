resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = var.aks_dns_prefix
  tags                = var.tags

  default_node_pool {
    name                = "odoo"
    vm_size             = var.aks_node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = var.aks_node_min_count
    max_count           = var.aks_node_max_count
    os_disk_size_gb     = var.aks_node_os_disk_gb
    zones               = var.aks_availability_zones
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    outbound_type  = "loadBalancer"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
    ]
  }
}

# Allow AKS nodes to mount Azure Blob (Blob Fuse CSI) for Odoo filestore.
resource "azurerm_role_assignment" "aks_blob_contributor" {
  scope                = azurerm_storage_account.backups.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
}
