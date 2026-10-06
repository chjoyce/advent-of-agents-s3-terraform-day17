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
  required_apis = [
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "agentregistry.googleapis.com",
    "modelarmor.googleapis.com",
    "serviceusage.googleapis.com",
  ]

  dep_p4sa_roles = [
    "roles/modelarmor.user",
    "roles/modelarmor.calloutUser",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/compute.networkUser",
    "roles/dns.peer",
  ]
}

# ------------------------------------------------------------------------------
# 1. APIs & Data Access Audit Logs
# ------------------------------------------------------------------------------

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_iam_audit_config" "vertex_data_access_logs" {
  project = var.project_id
  service = "aiplatform.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }

  depends_on = [
    google_project_service.apis
  ]
}

# Pre-create the Vertex AI Service Agents (gcp-sa-aiplatform & gcp-sa-aiplatform-re)
# and bind their IAM roles during Stage 1 so IAM propagation finishes while
# Cloud Build builds and pushes the container image in Steps 2 & 3.
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_service_identity" "vertex_agent" {
  provider = google-beta
  project  = var.project_id
  service  = "aiplatform.googleapis.com"

  depends_on = [
    google_project_service.apis
  ]
}

resource "google_project_iam_member" "vertex_gateway_verifier" {
  project = var.project_id
  role    = "roles/networkservices.admin"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-aiplatform.iam.gserviceaccount.com"

  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

resource "google_project_iam_member" "vertex_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-aiplatform.iam.gserviceaccount.com"

  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

resource "google_project_iam_member" "runtime_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"

  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

resource "google_project_iam_member" "runtime_gateway_verifier" {
  project = var.project_id
  role    = "roles/networkservices.admin"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"

  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

resource "google_project_iam_member" "runtime_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"

  depends_on = [
    google_project_service_identity.vertex_agent
  ]
}

# ------------------------------------------------------------------------------
# 2. Artifact Registry
# ------------------------------------------------------------------------------

resource "google_artifact_registry_repository" "agent_images" {
  location      = var.region
  repository_id = "agent-images"
  description   = "Container images for Agent Runtime"
  format        = "DOCKER"

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.dep_p4sa_roles,
  ]
}

# ------------------------------------------------------------------------------
# 3. VPC, Subnet & Network Attachment
# ------------------------------------------------------------------------------

resource "google_compute_network" "agent_vpc" {
  name                    = "agent-demo-vpc"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.apis
  ]
}

resource "google_compute_subnetwork" "agent_subnet" {
  name                     = "agent-demo-subnet"
  region                   = var.region
  network                  = google_compute_network.agent_vpc.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_network_attachment" "agent_gateway" {
  provider = google-beta

  name                  = "agent-demo-attachment"
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"

  subnetworks = [
    google_compute_subnetwork.agent_subnet.id
  ]
}

# ------------------------------------------------------------------------------
# 4. Agent Gateways — Ingress (CLIENT_TO_AGENT) & Egress (AGENT_TO_ANYWHERE)
# ------------------------------------------------------------------------------

resource "google_network_services_agent_gateway" "ingress" {
  provider = google-beta

  name     = "agent-demo-ingress"
  location = var.region

  google_managed {
    governed_access_path = "CLIENT_TO_AGENT"
  }

  depends_on = [
    google_project_service.apis,
    google_compute_network_attachment.agent_gateway,
  ]
}

resource "google_network_services_agent_gateway" "egress" {
  provider = google-beta

  name     = "agent-demo-egress"
  location = var.region

  google_managed {
    governed_access_path = "AGENT_TO_ANYWHERE"
  }

  network_config {
    egress {
      network_attachment = google_compute_network_attachment.agent_gateway.id
    }
  }

  depends_on = [
    google_project_service.apis
  ]
}

# Grant the Service Extensions / Data Egress Protection (DEP) Service Agent
# permissions to invoke Model Armor inline callouts and use project quota.
resource "google_project_iam_member" "dep_p4sa_roles" {
  for_each = toset(local.dep_p4sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${coalesce(try(google_network_services_agent_gateway.ingress.agent_gateway_card[0].service_extensions_service_account, null), "service-${data.google_project.current.number}@gcp-sa-dep.iam.gserviceaccount.com")}"

  depends_on = [
    google_network_services_agent_gateway.ingress,
    google_network_services_agent_gateway.egress,
  ]
}

# ------------------------------------------------------------------------------
# 5. Model Armor Security Templates (Prompt & Response Screening)
# ------------------------------------------------------------------------------

# Template 1: High-sensitivity screening for user prompts (ingress)
resource "google_model_armor_template" "agent_security" {
  project     = var.project_id
  location    = var.region
  template_id = "agent-demo-security"

  filter_config {
    pi_and_jailbreak_filter_settings {
      filter_enforcement = "ENABLED"
      confidence_level   = "HIGH"
    }

    malicious_uri_filter_settings {
      filter_enforcement = "ENABLED"
    }

    rai_settings {
      rai_filters {
        filter_type      = "HATE_SPEECH"
        confidence_level = "HIGH"
      }
      rai_filters {
        filter_type      = "HARASSMENT"
        confidence_level = "HIGH"
      }
      rai_filters {
        filter_type      = "SEXUALLY_EXPLICIT"
        confidence_level = "HIGH"
      }
      rai_filters {
        filter_type      = "DANGEROUS"
        confidence_level = "HIGH"
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = "ENABLED"
      }
    }
  }

  template_metadata {
    enforcement_type        = "INSPECT_AND_BLOCK"
    log_sanitize_operations = true
    log_template_operations = true
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.dep_p4sa_roles,
  ]
}

# Template 2: Response screening for LLM outputs
resource "google_model_armor_template" "security_responses" {
  project     = var.project_id
  location    = var.region
  template_id = "agent-demo-security-responses"

  filter_config {
    pi_and_jailbreak_filter_settings {
      filter_enforcement = "ENABLED"
      confidence_level   = "MEDIUM_AND_ABOVE"
    }

    malicious_uri_filter_settings {
      filter_enforcement = "ENABLED"
    }

    rai_settings {
      rai_filters {
        filter_type      = "HATE_SPEECH"
        confidence_level = "LOW_AND_ABOVE"
      }
      rai_filters {
        filter_type      = "HARASSMENT"
        confidence_level = "LOW_AND_ABOVE"
      }
      rai_filters {
        filter_type      = "SEXUALLY_EXPLICIT"
        confidence_level = "LOW_AND_ABOVE"
      }
      rai_filters {
        filter_type      = "DANGEROUS"
        confidence_level = "LOW_AND_ABOVE"
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = "ENABLED"
      }
    }
  }

  template_metadata {
    enforcement_type        = "INSPECT_AND_BLOCK"
    log_sanitize_operations = true
    log_template_operations = true
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.dep_p4sa_roles,
  ]
}

# ------------------------------------------------------------------------------
# 6. Model Armor Authz Extension & Policies on Ingress & Egress Gateways
# ------------------------------------------------------------------------------

resource "google_network_services_authz_extension" "ma_extension_ingress" {
  provider        = google-beta
  name            = "agent-demo-ma-extension-ingress"
  location        = var.region
  project         = var.project_id
  service         = "modelarmor.${var.region}.rep.googleapis.com"
  timeout         = "3s"
  fail_open       = var.ma_ingress_fail_open
  forward_headers = ["authorization"]

  metadata = {
    model_armor_settings = jsonencode([
      {
        request_template_id  = google_model_armor_template.agent_security.id
        response_template_id = google_model_armor_template.security_responses.id
      }
    ])
  }

  depends_on = [
    google_project_service.apis,
    google_model_armor_template.agent_security,
    google_model_armor_template.security_responses,
    google_project_iam_member.dep_p4sa_roles,
  ]
}

resource "google_network_security_authz_policy" "ingress_ma_policy" {
  provider       = google-beta
  name           = "agent-demo-ma-ingress-policy"
  location       = var.region
  project        = var.project_id
  action         = "CUSTOM"
  policy_profile = "CONTENT_AUTHZ"

  target {
    resources = [google_network_services_agent_gateway.ingress.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.ma_extension_ingress.id]
    }
  }
}

# Allow outbound calls from the Agent Runtime through the Egress Agent Gateway
# to Vertex AI / Gemini models, Cloud Logging, and Telemetry endpoints.
resource "google_network_security_authz_policy" "egress_allow_policy" {
  provider       = google-beta
  name           = "agent-demo-egress-allow-policy"
  location       = var.region
  project        = var.project_id
  action         = "ALLOW"
  policy_profile = "REQUEST_AUTHZ"

  target {
    resources = [google_network_services_agent_gateway.egress.id]
  }

  http_rules {
    to {
      operations {
        paths {
          prefix = "/"
        }
      }
    }
  }
}
