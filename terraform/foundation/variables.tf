variable "project_id" {
  type        = string
  description = "Google Cloud Project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Google Cloud region for foundation resources"
}

variable "repository_name" {
  type        = string
  default     = "agent-repo"
  description = "Artifact Registry Docker repository name for agent images"
}

variable "vpc_name" {
  type        = string
  default     = "agent-demo-vpc"
  description = "VPC network name for agent infrastructure"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.10.0.0/24"
  description = "Primary CIDR range for the regional agent subnet"
}

variable "model_armor_template_id" {
  type        = string
  default     = "agent-demo-safety-template"
  description = "Model Armor template ID for prompt injection and RAI guardrails"
}
