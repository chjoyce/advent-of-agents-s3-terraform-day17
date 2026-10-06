terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.45.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.45.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

locals {
  class_methods = [
    {
      name        = "get_session"
      api_mode    = ""
      description = "Retrieve session by ID"
      parameters = {
        type     = "object"
        required = ["user_id", "session_id"]
        properties = {
          user_id    = { type = "string" }
          session_id = { type = "string" }
        }
      }
    },
    {
      name        = "list_sessions"
      api_mode    = ""
      description = "List all sessions for a user"
      parameters = {
        type     = "object"
        required = ["user_id"]
        properties = {
          user_id = { type = "string" }
        }
      }
    },
    {
      name        = "create_session"
      api_mode    = ""
      description = "Create a new session"
      parameters = {
        type     = "object"
        required = ["user_id"]
        properties = {
          user_id    = { type = "string" }
          session_id = { type = "string" }
          state      = { type = "object" }
        }
      }
    },
    {
      name        = "delete_session"
      api_mode    = ""
      description = "Delete session by ID"
      parameters = {
        type     = "object"
        required = ["user_id", "session_id"]
        properties = {
          user_id    = { type = "string" }
          session_id = { type = "string" }
        }
      }
    },
    {
      name        = "async_get_session"
      api_mode    = "async"
      description = "Retrieve session asynchronously by ID"
      parameters = {
        type     = "object"
        required = ["user_id", "session_id"]
        properties = {
          user_id    = { type = "string" }
          session_id = { type = "string" }
        }
      }
    },
    {
      name        = "async_list_sessions"
      api_mode    = "async"
      description = "List all sessions for a user asynchronously"
      parameters = {
        type     = "object"
        required = ["user_id"]
        properties = {
          user_id = { type = "string" }
        }
      }
    },
    {
      name        = "async_create_session"
      api_mode    = "async"
      description = "Create a new session asynchronously"
      parameters = {
        type     = "object"
        required = ["user_id"]
        properties = {
          user_id    = { type = "string" }
          session_id = { type = "string" }
          state      = { type = "object" }
        }
      }
    },
    {
      name        = "async_delete_session"
      api_mode    = "async"
      description = "Delete session asynchronously by ID"
      parameters = {
        type     = "object"
        required = ["user_id", "session_id"]
        properties = {
          user_id    = { type = "string" }
          session_id = { type = "string" }
        }
      }
    },
    {
      name        = "stream_query"
      api_mode    = "stream"
      description = "Stream queries from the agent"
      parameters = {
        type     = "object"
        required = ["message", "user_id"]
        properties = {
          message    = { description = "Message string or object" }
          user_id    = { type = "string" }
          session_id = { type = "string" }
          run_config = { type = "object" }
        }
      }
    },
    {
      name        = "async_stream_query"
      api_mode    = "async_stream"
      description = "Stream queries asynchronously from the agent"
      parameters = {
        type     = "object"
        required = ["message", "user_id"]
        properties = {
          message        = { description = "Message string or object" }
          user_id        = { type = "string" }
          session_id     = { type = "string" }
          session_events = { type = "array", items = { type = "object" } }
          run_config     = { type = "object" }
        }
      }
    },
    {
      name        = "streaming_agent_run_with_events"
      api_mode    = "async_stream"
      description = "Stream agent run with events asynchronously"
      parameters = {
        type     = "object"
        required = ["request_json"]
        properties = {
          request_json = { type = "string" }
        }
      }
    }
  ]

  agent_identity_roles = [
    "roles/aiplatform.user",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
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
    # Note: GOOGLE_CLOUD_PROJECT and GOOGLE_CLOUD_QUOTA_PROJECT are automatically injected by Agent Engine.
    deployment_spec {
      env {
        name  = "GOOGLE_CLOUD_LOCATION"
        value = var.region
      }
      env {
        name  = "GOOGLE_GENAI_USE_VERTEXAI"
        value = "1"
      }
      env {
        name  = "GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES"
        value = "false"
      }

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

# ---------------------------------------------------------
# Grant the Agent Identity (SPIFFE principal) least-privilege
# permissions to call Gemini models, consume quota, and log.
# ---------------------------------------------------------
resource "google_project_iam_member" "agent_identity_roles" {
  for_each = toset(local.agent_identity_roles)

  project = var.project_id
  role    = each.value
  member  = "principal://${google_vertex_ai_reasoning_engine.agent.spec[0].effective_identity}"
}
