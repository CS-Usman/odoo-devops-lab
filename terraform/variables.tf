variable "location" {
  description = "Azure region"
  type        = string
  default     = "indiasouthcentral"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-odoo-devops-lab"
}

variable "vm_name" {
  description = "Linux VM name"
  type        = string
  default     = "vm-odoo-lab"
}

variable "vm_size" {
  description = "VM size (B1ms/B2s — if SkuNotAvailable, try another size or region)"
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "SSH login user on the VM"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM login — Azure requires RSA (ssh-rsa), not ed25519"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your IP/CIDR allowed to SSH (use your public IP/32)"
  type        = string
  default     = "*"
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default = {
    project = "odoo-devops-lab"
    env     = "lab"
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
  description = "Private DNS zone — must end with .postgres.database.azure.com and must NOT match postgres_server_name"
  type        = string
  default     = "odoo-devops-lab.postgres.database.azure.com"
}

variable "postgres_database_name" {
  description = "Database created for Odoo"
  type        = string
  default     = "odoo_devops_lab"
}

variable "postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "postgres_sku_name" {
  description = "Burstable B1ms is cheap for lab; change if SkuNotAvailable in your region"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB (minimum 32768 for Flexible Server)"
  type        = number
  default     = 32768
}

variable "storage_account_name" {
  description = "Globally unique storage account name (3-24 lowercase letters/numbers)"
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
