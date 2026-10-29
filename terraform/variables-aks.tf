variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-odoo-devops-lab"
}

variable "aks_dns_prefix" {
  description = "AKS DNS prefix (must be unique in region)"
  type        = string
  default     = "odoo-devops-lab"
}

variable "aks_node_vm_size" {
  description = "AKS user node pool VM SKU"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "aks_node_min_count" {
  description = "Minimum worker nodes (2 for basic HA)"
  type        = number
  default     = 2
}

variable "aks_node_max_count" {
  description = "Maximum worker nodes (hard-capped at 2 for this lab — same as min for a fixed 2-VM pool)"
  type        = number
  default     = 2

  validation {
    condition     = var.aks_node_max_count == 2 && var.aks_node_min_count == 2
    error_message = "This lab uses exactly 2 AKS worker VMs: set aks_node_min_count and aks_node_max_count both to 2."
  }
}

variable "aks_node_os_disk_gb" {
  description = "OS disk size per AKS node"
  type        = number
  default     = 128
}

variable "aks_availability_zones" {
  description = "Spread nodes across zones (use [\"1\",\"2\"] when region supports it)"
  type        = list(string)
  default     = ["1", "2"]
}

variable "postgres_ha_enabled" {
  description = "Zone-redundant HA on Flexible Server (requires GP tier in most regions)"
  type        = bool
  default     = false
}

variable "postgres_ha_standby_zone" {
  type    = string
  default = "1"
}

variable "postgres_zone" {
  type    = string
  default = "2"
}

variable "postgres_backup_retention_days" {
  type    = number
  default = 14
}

variable "postgres_geo_redundant_backup" {
  type    = bool
  default = false
}
