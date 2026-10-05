variable "project_id" {
  type        = string
  description = "Google Cloud project ID."
}

variable "region" {
  type        = string
  description = "Google Cloud region."
  default     = "us-central1"
}

variable "ma_ingress_fail_open" {
  type        = bool
  description = "Whether the Ingress Model Armor Authz Extension fails open if Model Armor or callout IAM is unreachable. Set to false for strict fail-closed enforcement."
  default     = true
}
