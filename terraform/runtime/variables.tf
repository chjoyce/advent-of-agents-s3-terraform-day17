variable "project_id" {
  type        = string
  description = "Google Cloud Project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Google Cloud region to deploy Vertex AI Agent Runtime"
}

variable "repository_name" {
  type        = string
  default     = "agent-repo"
  description = "Artifact Registry Docker repository name (created in terraform/foundation)"
}

variable "agent_name" {
  type        = string
  default     = "day17-adk-ops-agent"
  description = "Display name and container image name for the single ADK agent"
}

variable "image_tag" {
  type        = string
  default     = "v1.0.0"
  description = "Immutable container image tag built and pushed by Cloud Build"
}

variable "model_name" {
  type        = string
  default     = "gemini-2.5-flash"
  description = "Gemini model used by the ADK agent"
}

variable "model_armor_template_id" {
  type        = string
  default     = "agent-demo-safety-template"
  description = "Model Armor template ID provisioned in terraform/foundation"
}
