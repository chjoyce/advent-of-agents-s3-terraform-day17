output "reasoning_engine_id" {
  value       = google_vertex_ai_reasoning_engine.agent.name
  description = "The ID of the deployed Vertex AI Agent Runtime instance"
}

output "reasoning_engine_full_name" {
  value       = "projects/${var.project_id}/locations/${var.region}/reasoningEngines/${google_vertex_ai_reasoning_engine.agent.name}"
  description = "Full resource name of the deployed Vertex AI Agent Runtime instance"
}

output "agent_effective_identity" {
  value       = try(google_vertex_ai_reasoning_engine.agent.spec[0].effective_identity, "")
  description = "Provisioned SPIFFE / W3C Agent Identity principal for the Agent Runtime"
}

output "deployed_image_uri" {
  value       = local.image_uri
  description = "Immutable container image URI running on Vertex AI Agent Runtime"
}

output "stream_query_url" {
  value       = "https://${var.region}-aiplatform.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/reasoningEngines/${google_vertex_ai_reasoning_engine.agent.name}:streamQuery?alt=sse"
  description = "HTTPS streaming endpoint for querying the deployed ADK agent"
}
