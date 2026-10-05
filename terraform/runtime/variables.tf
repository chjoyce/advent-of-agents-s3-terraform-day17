variable "project_id" {
  type        = string
  description = "Google Cloud project ID."
}

variable "project_number" {
  type        = string
  description = "Google Cloud project number."
}

variable "region" {
  type        = string
  description = "Google Cloud region."
  default     = "us-central1"
}

variable "image_tag" {
  type        = string
  description = "Container image tag to deploy."
  default     = "manual"
}

variable "repository_name" {
  type        = string
  description = "Artifact Registry repository name."
  default     = "agent-images"
}

variable "ingress_gateway_id" {
  type        = string
  description = "Client-to-Agent Agent Gateway resource ID."
}

variable "egress_gateway_id" {
  type        = string
  description = "Agent-to-Anywhere Agent Gateway resource ID."
}
