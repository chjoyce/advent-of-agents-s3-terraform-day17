output "artifact_registry_repository" {
  description = "Artifact Registry repository ID."
  value       = google_artifact_registry_repository.agent_images.name
}

output "artifact_registry_repository_url" {
  description = "Artifact Registry repository URL."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_images.repository_id}"
}

output "vpc_name" {
  description = "Agent VPC name."
  value       = google_compute_network.agent_vpc.name
}

output "network_attachment_id" {
  description = "Network Attachment resource ID."
  value       = google_compute_network_attachment.agent_gateway.id
}

output "ingress_gateway_id" {
  description = "Client-to-Agent Agent Gateway ID."
  value       = google_network_services_agent_gateway.ingress.id
}

output "egress_gateway_id" {
  description = "Agent-to-Anywhere Agent Gateway ID."
  value       = google_network_services_agent_gateway.egress.id
}

output "model_armor_template_id" {
  description = "Primary Model Armor prompt security template ID."
  value       = google_model_armor_template.agent_security.id
}

output "model_armor_response_template_id" {
  description = "Model Armor LLM response security template ID."
  value       = google_model_armor_template.security_responses.id
}

output "ingress_ma_policy_id" {
  description = "Ingress Model Armor CONTENT_AUTHZ policy ID."
  value       = google_network_security_authz_policy.ingress_ma_policy.id
}

output "egress_ma_policy_id" {
  description = "Egress Model Armor CONTENT_AUTHZ policy ID."
  value       = google_network_security_authz_policy.egress_ma_policy.id
}
