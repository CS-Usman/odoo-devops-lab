variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-odoo-devops-lab"
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default = {
    project = "odoo-devops-lab"
    env     = "production"
  }
}

variable "postgres_server_name" {
  description = "Azure PostgreSQL Flexible Server name (lowercase, globally unique)"
  type        = string
  default     = "psql-odoo-devops-lab"
}

variable "postgres_admin_login" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "odooadmin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password (min 8 chars, upper/lower/number/special)"
  type        = string
  sensitive   = true
}

variable "postgres_private_dns_zone_name" {
  description = "Private DNS zone — must end with .postgres.database.azure.com"
  type        = string
  default     = "odoo-devops-lab.postgres.database.azure.com"
}

variable "postgres_database_name" {
  description = "Production database for Odoo"
  type        = string
  default     = "odoo_devops_lab"
}

variable "postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "postgres_sku_name" {
  description = "PostgreSQL SKU (e.g. GP_Standard_D2s_v3 for production-style lab)"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB (minimum 32768 for Flexible Server)"
  type        = number
  default     = 32768
}

variable "storage_account_name" {
  description = "Globally unique storage account for backup blobs"
  type        = string
  default     = "stodoodevopslab"
}

variable "storage_container_name" {
  description = "Private blob container for pg_dump + filestore archives"
  type        = string
  default     = "odoo-backups"
}

variable "backup_retention_days" {
  description = "Auto-delete backup blobs older than this many days"
  type        = number
  default     = 30
}

variable "odoo_prod_filestore_container_name" {
  description = "Blob container — canonical production Odoo filestore (Blob Fuse / sync)"
  type        = string
  default     = "odoo-prod-filestore"
}

variable "odoo_staging_filestore_container_name" {
  description = "Blob container — staging filestore copy (refreshed from prod)"
  type        = string
  default     = "odoo-staging-filestore"
}
