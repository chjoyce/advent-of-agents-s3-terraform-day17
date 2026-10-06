terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.45.0"
    }
  }

  backend "gcs" {}
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

locals {
  class_methods = [
    {
      name     = "get_session"
      api_mode = ""
    },
    {
      name     = "list_sessions"
      api_mode = ""
    },
    {
      name     = "create_session"
      api_mode = ""
    },
    {
      name     = "delete_session"
      api_mode = ""
    },
    {
      name     = "async_get_session"
      api_mode = "async"
    },
    {
      name     = "async_list_sessions"
      api_mode = "async"
    },
    {
      name     = "async_create_session"
      api_mode = "async"
    },
    {
      name     = "async_delete_session"
      api_mode = "async"
    },
    {
      name     = "stream_query"
      api_mode = "stream"
    },
    {
      name     = "async_stream_query"
      api_mode = "async_stream"
    },
    {
      name     = "streaming_agent_run_with_events"
      api_mode = "async_stream"
    }
  ]
}

# ---------------------------------------------------------
# Force creation of Vertex AI Service Identity / P4SA
# ---------------------------------------------------------
resource "google_project_service_identity" "vertex_agent" {
  provider = google-beta
  project  = var.project_id
  service  = "aiplatform.googleapis.com"
}

# ---------------------------------------------------------
# Give Vertex AI Service Agent permission to get and use Agent Gateways
# ---------------------------------------------------------
resource "google_project_iam_member" "vertex_gateway_verifier" {
  project = var.project_id
  role    = "roles/networkservices.admin"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform.iam.gserviceaccount.com"

  # Wait for the primary service agent identity to exist
  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

# ---------------------------------------------------------
# Give Agent Runtime permission to pull our image
# ---------------------------------------------------------
resource "google_project_iam_member" "runtime_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"

  # CRITICAL: Wait for Vertex identity to be provisioned before setting policy
  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

# ---------------------------------------------------------
# Agent Runtime (routed through Ingress & Egress Agent Gateways)
# ---------------------------------------------------------
resource "google_vertex_ai_reasoning_engine" "agent" {
  provider     = google-beta
  project      = var.project_id
  region       = var.region
  display_name = "terraform-demo-agent"
  description  = "ADK agent deployed through Terraform and Cloud Build behind Agent Gateway and Model Armor"

  spec {
    agent_framework = "google-adk"

    # Mints a cryptographic SPIFFE-based Agent Identity rather than a shared service account.
    identity_type = "AGENT_IDENTITY"

    container_spec {
      image_uri = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_name}/demo-agent:${var.image_tag}"
    }

    class_methods = jsonencode(local.class_methods)

    # Route the agent through the Client-to-Agent (Ingress) and Agent-to-Anywhere (Egress) Agent Gateways.
    deployment_spec {
      agent_gateway_config {
        client_to_agent_config {
          agent_gateway = var.ingress_gateway_id
        }
        agent_to_anywhere_config {
          agent_gateway = var.egress_gateway_id
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.vertex_gateway_verifier,
    google_project_iam_member.runtime_artifact_reader,
  ]
}
