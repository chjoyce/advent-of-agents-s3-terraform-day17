# ==============================================================================
# STAGE 2: SINGLE AGENT RUNTIME PROVISIONING (Vertex AI Agent Runtime + SPIFFE)
# ==============================================================================

data "google_project" "project" {
  project_id = var.project_id
}

locals {
  image_uri = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_name}/${var.agent_name}:${var.image_tag}"

  # Standard ADK operations exposed by AdkApp over the Agent Runtime Contract
  adk_class_methods = [
    { "name" = "get_session", "api_mode" = "" },
    { "name" = "list_sessions", "api_mode" = "" },
    { "name" = "create_session", "api_mode" = "" },
    { "name" = "delete_session", "api_mode" = "" },
    { "name" = "async_get_session", "api_mode" = "async" },
    { "name" = "async_list_sessions", "api_mode" = "async" },
    { "name" = "async_create_session", "api_mode" = "async" },
    { "name" = "async_delete_session", "api_mode" = "async" },
    { "name" = "stream_query", "api_mode" = "stream" },
    { "name" = "async_stream_query", "api_mode" = "async_stream" },
  ]
}

# 1. Ensure Vertex AI Reasoning Engine Service Agent can pull from Artifact Registry
resource "google_project_iam_member" "re_service_agent_ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}

# 2. Provision the Single ADK Agent on Vertex AI Agent Runtime
resource "google_vertex_ai_reasoning_engine" "agent" {
  provider     = google-beta
  display_name = var.agent_name
  description  = "Single ADK Agent provisioned declaratively via Terraform and deployed by Cloud Build"
  project      = var.project_id
  region       = var.region

  spec {
    agent_framework = "google-adk"

    # Provisions a cryptographic W3C / SPIFFE Agent Identity (principal://...)
    identity_type = "AGENT_IDENTITY"

    # Deploys the exact immutable container image built by Cloud Build
    container_spec {
      image_uri = local.image_uri
    }

    deployment_spec {
      min_instances         = 1
      max_instances         = 4
      container_concurrency = 9

      resource_limits = {
        cpu    = "2"
        memory = "4Gi"
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "GOOGLE_CLOUD_LOCATION"
        value = var.region
      }
      env {
        name  = "GOOGLE_GENAI_USE_VERTEXAI"
        value = "TRUE"
      }
      env {
        name  = "MODEL"
        value = var.model_name
      }
      env {
        name  = "IMAGE_TAG"
        value = var.image_tag
      }
      env {
        name  = "MODEL_ARMOR_TEMPLATE_ID"
        value = var.model_armor_template_id
      }
    }

    class_methods = jsonencode(local.adk_class_methods)
  }

  # Prevent IMAGE_PULL_BACKOFF race condition during initial deployment
  depends_on = [google_project_iam_member.re_service_agent_ar_reader]
}
