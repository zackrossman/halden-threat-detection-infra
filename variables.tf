variable "subscription_id" {
  description = "Azure subscription that owns the Halden platform resources."
  type        = string
}

variable "environment" {
  description = "Environment label used in resource names and tags. This state manages the production deployment."
  type        = string
  default     = "production"
}

variable "location" {
  description = "Azure region for the resources created here."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group holding the Halden platform resources."
  type        = string
}

variable "cluster_name" {
  description = "Name of the existing AKS cluster that runs the Halden services."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the Halden services run in."
  type        = string
  default     = "halden"
}

variable "virtual_network_name" {
  description = "Virtual network the AKS cluster is attached to."
  type        = string
}

variable "database_subnet_name" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "container_registry" {
  description = "Login server of the registry holding the halden-threat-detection image."
  type        = string
}

variable "image_tag" {
  description = "Image tag of halden-threat-detection to deploy. Set by the release pipeline."
  type        = string
}

variable "replica_count" {
  description = "Number of halden-threat-detection pods."
  type        = number
  default     = 3

  validation {
    condition     = var.replica_count >= 2
    error_message = "Run at least two replicas so a rolling update does not drop traffic."
  }
}

variable "cpu_request" {
  description = "CPU reserved per pod."
  type        = string
  default     = "250m"
}

variable "cpu_limit" {
  description = "CPU ceiling per pod."
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory reserved per pod."
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory ceiling per pod."
  type        = string
  default     = "1Gi"
}

variable "postgres_sku_name" {
  description = "SKU of the PostgreSQL flexible server."
  type        = string
  default     = "GP_Standard_D2ds_v4"
}

variable "postgres_storage_mb" {
  description = "Storage allocated to the PostgreSQL flexible server."
  type        = number
  default     = 65536
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "postgres_administrator_login" {
  description = "Administrator login for the PostgreSQL flexible server."
  type        = string
  default     = "haldenadmin"
}

variable "postgres_administrator_password" {
  description = "Administrator password for the PostgreSQL flexible server. Supply via TF_VAR_postgres_administrator_password; never commit it."
  type        = string
  sensitive   = true
}

variable "halden_gateway_key" {
  description = "Shared key halden-identity presents when calling this service. Supply via TF_VAR_halden_gateway_key; never commit it."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to every Azure resource created here."
  type        = map(string)
  default     = {}
}
