output "project_id" {
  value       = var.project_id
  description = "Google Cloud Project ID"
}

output "project_number" {
  value       = data.google_project.project.number
  description = "Google Cloud Project Number"
}

output "artifact_registry_repo_name" {
  value       = google_artifact_registry_repository.agent_repo.repository_id
  description = "Artifact Registry Docker repository name"
}

output "artifact_registry_uri" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_repo.repository_id}"
  description = "Base Artifact Registry URI for pushing agent container images"
}

output "agent_service_account_email" {
  value       = google_service_account.agent_runtime_sa.email
  description = "Dedicated service account email for the ADK agent"
}

output "vpc_network_name" {
  value       = google_compute_network.agent_vpc.name
  description = "Provisioned VPC network name"
}

output "vpc_subnet_name" {
  value       = google_compute_subnetwork.agent_subnet.name
  description = "Provisioned regional subnet name"
}

output "model_armor_template_id" {
  value       = google_model_armor_template.agent_safety.template_id
  description = "Model Armor safety template ID"
}

output "model_armor_template_name" {
  value       = google_model_armor_template.agent_safety.name
  description = "Full resource name of the Model Armor safety template"
}
