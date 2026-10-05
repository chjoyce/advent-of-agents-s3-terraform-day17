output "agent_runtime_id" {
  description = "Agent Runtime resource ID."
  value       = google_vertex_ai_reasoning_engine.agent.id
}

output "agent_runtime_name" {
  description = "Full Agent Runtime resource name."
  value       = google_vertex_ai_reasoning_engine.agent.name
}

output "agent_runtime_image" {
  description = "Container image currently deployed."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_name}/demo-agent:${var.image_tag}"
}
