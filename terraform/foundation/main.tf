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
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "networkservices.googleapis.com",
    "networksecurity.googleapis.com",
    "agentregistry.googleapis.com",
    "modelarmor.googleapis.com",
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

# ------------------------------------------------------------------------------
# 2. Artifact Registry
# ------------------------------------------------------------------------------

resource "google_artifact_registry_repository" "agent_images" {
  location      = var.region
  repository_id = "agent-images"
  description   = "Container images for Agent Runtime"
  format        = "DOCKER"

  depends_on = [
    google_project_service.apis
  ]
}

# ------------------------------------------------------------------------------
# 3. VPC, Subnet, PSC Egress VIP Firewall & Network Attachment
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

# Allow egress to 240.0.0.0/4 (GCP PSC gateway Class E VIP range, e.g. 240.0.0.2).
# Required for PSC egress interception to reach the Agent Gateway SWP.
resource "google_compute_firewall" "psc_egress_vip_allow" {
  name    = "agent-demo-psc-egress-vip-allow"
  network = google_compute_network.agent_vpc.name
  project = var.project_id

  description = "Allow egress to 240.0.0.0/4 (GCP PSC gateway Class E VIP range) for Agent Gateway egress interception."
  direction   = "EGRESS"
  priority    = 900

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  destination_ranges = ["240.0.0.0/4"]

  depends_on = [
    google_project_service.apis
  ]
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

  name      = "agent-demo-ingress"
  location  = var.region
  protocols = ["MCP"]

  google_managed {
    governed_access_path = "CLIENT_TO_AGENT"
  }

  depends_on = [
    google_project_service.apis
  ]
}

resource "google_network_services_agent_gateway" "egress" {
  provider = google-beta

  name      = "agent-demo-egress"
  location  = var.region
  protocols = ["MCP"]

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

# ------------------------------------------------------------------------------
# 5. Model Armor Security Templates (Prompt & Response Screening)
# ------------------------------------------------------------------------------

# Template 1: High-sensitivity screening for user prompts (ingress) and outbound tool calls
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
    google_project_service.apis
  ]
}

# Template 2: Response screening for LLM outputs returning via the Egress Gateway
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
    google_project_service.apis
  ]
}

# ------------------------------------------------------------------------------
# 6. Model Armor Authz Extensions & Content Authz Policies on Agent Gateways
# ------------------------------------------------------------------------------

resource "google_network_services_authz_extension" "ma_extension_ingress" {
  provider  = google-beta
  name      = "agent-demo-ma-extension-ingress"
  location  = var.region
  project   = var.project_id
  service   = "modelarmor.${var.region}.rep.googleapis.com"
  timeout   = "3s"
  fail_open = var.ma_ingress_fail_open

  metadata = {
    model_armor_settings = jsonencode([
      {
        request_template_id = google_model_armor_template.agent_security.id
      }
    ])
  }

  depends_on = [
    google_project_service.apis,
    google_model_armor_template.agent_security,
  ]
}

resource "google_network_services_authz_extension" "ma_extension_egress" {
  provider  = google-beta
  name      = "agent-demo-ma-extension-egress"
  location  = var.region
  project   = var.project_id
  service   = "modelarmor.${var.region}.rep.googleapis.com"
  timeout   = "3s"
  fail_open = true

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

resource "google_network_security_authz_policy" "egress_ma_policy" {
  provider       = google-beta
  name           = "agent-demo-ma-egress-policy"
  location       = var.region
  project        = var.project_id
  action         = "CUSTOM"
  policy_profile = "CONTENT_AUTHZ"

  target {
    resources = [google_network_services_agent_gateway.egress.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.ma_extension_egress.id]
    }
  }

  http_rules {
    to {
      operations {
        hosts {
          suffix = ".aiplatform.googleapis.com"
        }
        paths {
          contains    = "generatecontent"
          ignore_case = true
        }
        paths {
          contains    = "predict"
          ignore_case = true
        }
        paths {
          contains    = "streamquery"
          ignore_case = true
        }
        paths {
          contains    = "sessions"
          ignore_case = true
        }
        paths {
          contains    = "events"
          ignore_case = true
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# 7. IAP Request Authz Extensions & Policies (DRY_RUN for Playground Visibility)
# ------------------------------------------------------------------------------

resource "google_network_services_authz_extension" "iap_extension_ingress" {
  provider  = google-beta
  name      = "agent-demo-iap-extension-ingress"
  location  = var.region
  project   = var.project_id
  service   = "iap.googleapis.com"
  timeout   = "1s"
  fail_open = true

  metadata = {
    iapPolicyVersion   = "V1"
    iamEnforcementMode = "DRY_RUN"
  }

  depends_on = [
    google_project_service.apis
  ]
}

resource "google_network_services_authz_extension" "iap_extension_egress" {
  provider  = google-beta
  name      = "agent-demo-iap-extension-egress"
  location  = var.region
  project   = var.project_id
  service   = "iap.googleapis.com"
  timeout   = "1s"
  fail_open = true

  metadata = {
    iapPolicyVersion   = "V1"
    iamEnforcementMode = "DRY_RUN"
  }

  depends_on = [
    google_project_service.apis
  ]
}

resource "google_network_security_authz_policy" "ingress_iap_policy" {
  provider       = google-beta
  name           = "agent-demo-iap-ingress-policy"
  location       = var.region
  project        = var.project_id
  action         = "CUSTOM"
  policy_profile = "REQUEST_AUTHZ"

  target {
    resources = [google_network_services_agent_gateway.ingress.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.iap_extension_ingress.id]
    }
  }

  depends_on = [
    google_network_services_authz_extension.iap_extension_ingress
  ]
}

resource "google_network_security_authz_policy" "egress_iap_policy" {
  provider       = google-beta
  name           = "agent-demo-iap-egress-policy"
  location       = var.region
  project        = var.project_id
  action         = "CUSTOM"
  policy_profile = "REQUEST_AUTHZ"

  target {
    resources = [google_network_services_agent_gateway.egress.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.iap_extension_egress.id]
    }
  }

  depends_on = [
    google_network_services_authz_extension.iap_extension_egress
  ]
}
