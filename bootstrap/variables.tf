variable "subscription_id" {
  description = "Azure subscription ID for the flagship project"
  type        = string
  # Default omitted on purpose — set via terraform.tfvars or TF_VAR_subscription_id
}

variable "location" {
  description = "Primary Azure region"
  type        = string
  default     = "canadacentral"
}

variable "alert_email" {
  description = "Email address that receives budget and security alerts"
  type        = string
}
