# ==============================================================================
# STAGE 1: FOUNDATION INFRASTRUCTURE (APIs, IAM, Artifact Registry, VPC, Model Armor)
# ==============================================================================

data "google_project" "project" {
  project_id = var.project_id
}

locals {
  enabled_services = [
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "aiplatform.googleapis.com",
    "agentregistry.googleapis.com",
    "modelarmor.googleapis.com",
  ]

  rai_filters = [
    { filter_type = "HATE_SPEECH", confidence_level = "MEDIUM_AND_ABOVE" },
    { filter_type = "HARASSMENT", confidence_level = "MEDIUM_AND_ABOVE" },
    { filter_type = "DANGEROUS", confidence_level = "MEDIUM_AND_ABOVE" },
    { filter_type = "SEXUALLY_EXPLICIT", confidence_level = "MEDIUM_AND_ABOVE" },
  ]
}

# 1. Enable Required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each           = toset(local.enabled_services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# 2. Provision Service Identities for Vertex AI & Model Armor
resource "google_project_service_identity" "vertex_sa" {
  provider   = google-beta
  project    = var.project_id
  service    = "aiplatform.googleapis.com"
  depends_on = [google_project_service.apis]
}

resource "google_project_service_identity" "model_armor_sa" {
  provider   = google-beta
  project    = var.project_id
  service    = "modelarmor.googleapis.com"
  depends_on = [google_project_service.apis]
}

# 3. Artifact Registry Docker Repository for Agent Container Images
resource "google_artifact_registry_repository" "agent_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_name
  description   = "Docker repository for ADK Agent Runtime container images"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# 4. Dedicated Least-Privilege Agent Service Account & IAM
resource "google_service_account" "agent_runtime_sa" {
  project      = var.project_id
  account_id   = "day17-agent-runtime-sa"
  display_name = "Day 17 ADK Agent Runtime Service Account"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "agent_runtime_sa_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/modelarmor.user",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.agent_runtime_sa.email}"
}

# Allow Vertex AI Service Agent to pull container images from Artifact Registry
resource "google_project_iam_member" "vertex_sa_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_project_service_identity.vertex_sa.email}"
}

# 5. VPC Network & Regional Subnet for Private Agent Connectivity
resource "google_compute_network" "agent_vpc" {
  project                 = var.project_id
  name                    = var.vpc_name
  auto_create_subnetworks = false
  description             = "Dedicated VPC network for Day 17 Agent Runtime demo"

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "agent_subnet" {
  project                  = var.project_id
  name                     = "${var.vpc_name}-subnet"
  region                   = var.region
  network                  = google_compute_network.agent_vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# 6. Model Armor Guardrail Template (Prompt Injection, Jailbreak & RAI Filtering)
resource "google_model_armor_template" "agent_safety" {
  project     = var.project_id
  location    = var.region
  template_id = var.model_armor_template_id

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = local.rai_filters
        content {
          filter_type      = rai_filters.value.filter_type
          confidence_level = rai_filters.value.confidence_level
        }
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = "ENABLED"
      confidence_level   = "MEDIUM_AND_ABOVE"
    }

    malicious_uri_filter_settings {
      filter_enforcement = "ENABLED"
    }
  }

  template_metadata {
    log_template_operations = true
    log_sanitize_operations = true
  }

  depends_on = [
    google_project_service.apis,
    google_project_service_identity.model_armor_sa,
  ]
}
