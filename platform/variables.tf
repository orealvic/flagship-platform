variable "subscription_id" {
  description = "Azure subscription ID where workloads are deployed"
  type        = string
}

variable "location" {
  description = "Primary Azure region"
  type        = string
  default     = "canadacentral"
}

variable "tenant_root_group_id" {
  description = "Tenant root group ID (defaults to tenant ID)"
  type        = string
  default     = ""
}

variable "log_analytics_daily_cap_gb" {
  description = "Daily ingestion cap on Log Analytics workspace (free tier ~5GB/month, we cap at 1GB/day to leave headroom)"
  type        = number
  default     = 1
}

variable "log_analytics_retention_days" {
  description = "Days of retention for Log Analytics workspace (30-day default is free)"
  type        = number
  default     = 30
}

variable "hub_vnet_address_space" {
  description = "Address space for the hub VNet"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}
