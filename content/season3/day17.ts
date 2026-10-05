import { DayContent } from '../types';

export const day17: DayContent = {
  day: 17,
  title: "Infrastructure as Code: Terraform & Cloud Build CI/CD",
  summary: "Pair Terraform with Cloud Build to package agent containers and declaratively deploy Agent Runtimes, Cloud Run, SPIFFE identities, Agent Gateways, Model Armor, and IAM in one CI/CD pipeline.",
  tags: ["Terraform", "Cloud Build", "CI/CD", "Governance"],
  icon: "🏗️",
  resourceLink: "https://docs.cloud.google.com/gemini-enterprise-agent-platform/scale/runtime/use-terraform",
  codeSnippets: [
    {
      filename: "terraform/foundation/main.tf",
      language: "hcl",
      code: `# 1. Ingress & Egress Agent Gateways (CLIENT_TO_AGENT & AGENT_TO_ANYWHERE)
resource "google_network_services_agent_gateway" "ingress" {
  provider  = google-beta
  name      = "agent-demo-ingress"
  location  = var.region
  protocols = ["MCP"]
  google_managed {
    governed_access_path = "CLIENT_TO_AGENT"
  }
}

resource "google_network_services_agent_gateway" "egress" {
  provider  = google-beta
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
}

# 2. Wire Model Armor Template into the Ingress Agent Gateway via Authz Policy
resource "google_network_services_authz_extension" "ma_extension_ingress" {
  provider  = google-beta
  name      = "agent-demo-ma-extension-ingress"
  location  = var.region
  service   = "modelarmor.\${var.region}.rep.googleapis.com"
  timeout   = "3s"
  fail_open = false
  metadata = {
    model_armor_settings = jsonencode([
      { request_template_id = google_model_armor_template.agent_security.id }
    ])
  }
}

resource "google_network_security_authz_policy" "ingress_ma_policy" {
  provider       = google-beta
  name           = "agent-demo-ma-ingress-policy"
  location       = var.region
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
}`
    },
    {
      filename: "terraform/runtime/main.tf",
      language: "hcl",
      code: `# Deploy ADK Agent Runtime with SPIFFE Identity routed through Ingress & Egress Gateways
resource "google_vertex_ai_reasoning_engine" "agent" {
  provider     = google-beta
  project      = var.project_id
  region       = var.region
  display_name = "terraform-demo-agent"
  description  = "ADK agent deployed through Terraform and Cloud Build"

  spec {
    agent_framework = "google-adk"
    identity_type   = "AGENT_IDENTITY" # Mints cryptographic SPIFFE ID

    container_spec {
      image_uri = "\${var.region}-docker.pkg.dev/\${var.project_id}/\${var.repository_name}/demo-agent:\${var.image_tag}"
    }

    class_methods = jsonencode(local.class_methods)

    # Route all client-to-agent and agent-to-anywhere traffic through Agent Gateways
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
}`
    },
    {
      filename: "cloudbuild.yaml",
      language: "yaml",
      code: `steps:
  # 1. Foundation: Provision VPC, Agent Gateways, Model Armor & Authz Policies
  - name: hashicorp/terraform:1.13
    id: terraform-foundation
    entrypoint: sh
    args:
      - -c
      - |
        cd terraform/foundation
        terraform init -backend-config="bucket=\${_TF_BUCKET}" -backend-config="prefix=agent-demo/foundation"
        terraform apply -auto-approve -var="project_id=\${PROJECT_ID}" -var="region=\${_REGION}"
        terraform output -raw ingress_gateway_id > /workspace/ingress_gateway_id
        terraform output -raw egress_gateway_id > /workspace/egress_gateway_id

  # 2. Build & push the ADK chatbot container to Artifact Registry
  - name: gcr.io/cloud-builders/docker
    id: build-and-push-agent
    args: ["build", "-t", "\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/agent-images/demo-agent:\${_IMAGE_TAG}", "--push", "./agent"]

  # 3. Runtime: Deploy Vertex AI Agent Runtime bound to the Ingress & Egress Gateways
  - name: hashicorp/terraform:1.13
    id: terraform-runtime
    entrypoint: sh
    args:
      - -c
      - |
        cd terraform/runtime
        terraform init -backend-config="bucket=\${_TF_BUCKET}" -backend-config="prefix=agent-demo/runtime"
        terraform apply -auto-approve \\
          -var="project_id=\${PROJECT_ID}" \\
          -var="project_number=\${PROJECT_NUMBER}" \\
          -var="region=\${_REGION}" \\
          -var="image_tag=\${_IMAGE_TAG}" \\
          -var="ingress_gateway_id=\$(cat /workspace/ingress_gateway_id)" \\
          -var="egress_gateway_id=\$(cat /workspace/egress_gateway_id)"`
    }
  ],
  links: [
    {
      label: "Day 17 Code Kata",
      url: "https://github.com/chjoyce/advent-of-agents-s3-terraform-day17",
      description: "Terraform and Cloud Build agent deployment demo."
    },
    {
      label: "Provision Agents with Terraform",
      url: "https://docs.cloud.google.com/gemini-enterprise-agent-platform/scale/runtime/use-terraform",
      description: "Deploy Agent Runtimes, identities, and gateways."
    },
    {
      label: "Terraform & Cloud Build GitOps",
      url: "https://docs.cloud.google.com/docs/terraform/resource-management/managing-infrastructure-as-code",
      description: "Automate Terraform plan and apply in CI/CD."
    },
    {
      label: "Terraform for Agent Platform",
      url: "https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/start/use-terraform-vertex-ai",
      description: "Configure Terraform providers and Vertex AI resources."
    }
  ],
  description: `
**Day 17 of Google's Advent of Agents — Season 3**

Prototyping with \`agents-cli\` is great for speed, but production demands reproducible Infrastructure as Code (IaC). Pairing **Terraform** with **Cloud Build** lets you build agent containers and declaratively deploy your entire stack (**Agent Runtimes, Cloud Run, SPIFFE identities, Agent Gateways, Model Armor, and IAM**) in one CI/CD pipeline.

**How It Works**

- **Define everything in Terraform**: Declare Agent Runtimes, Cloud Run, Agent Gateways, Model Armor, SPIFFE identities, IAM, networking, and secrets, backed by Cloud Storage state.
- **Build the agent**: Cloud Build packages the agent container and pushes it to Artifact Registry (or bundles the source archive).
- **Run Terraform in CI/CD**: Cloud Build runs \`terraform init\` and \`terraform plan\` on pull requests, and \`terraform apply\` on merge.
- **Provision and deploy**: Terraform updates the infrastructure and deploys the Agent Runtime and Cloud Run services with the new image.
- **Repeat on changes**: Every code or infra commit triggers Cloud Build → builds the new image → Terraform updates the live deployment.

**Resources:**
- [Provision Agents with Terraform](https://docs.cloud.google.com/gemini-enterprise-agent-platform/scale/runtime/use-terraform)
- [Terraform on Google Cloud](https://docs.cloud.google.com/docs/terraform)
- [Terraform & Cloud Build GitOps](https://docs.cloud.google.com/docs/terraform/resource-management/managing-infrastructure-as-code)
- [Terraform Compliance with Cloud Build](https://cloud.google.com/blog/products/devops-sre/terraform-gitops-with-google-cloud-build-and-storage)
- [Terraform for Agent Platform](https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/start/use-terraform-vertex-ai)
- [Terraform Blueprints Catalog](https://cloud.google.com/docs/terraform/blueprints/terraform-blueprints)
`,
  videoURL: "TODO"
};
