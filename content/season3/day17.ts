import { DayContent } from '../types';

export const day17: DayContent = {
    day: 17,
    title: "Infrastructure as Code (IaC) & Production CI/CD",
    summary: "Automate production ADK agent deployment with two-stage Terraform state in GCS, Model Armor guardrails, and Cloud Build pipelines.",
    tags: ["Terraform", "Cloud Build", "Agent Runtime", "CI/CD"],
    icon: "🏗️",
    resourceLink: "https://github.com/chjoyce/advent-of-agents-s3-terraform-day17",
    codeSnippets: [
        {
            filename: "terraform/runtime/main.tf",
            language: "hcl",
            code: `resource "google_vertex_ai_reasoning_engine" "agent" {
  provider     = google-beta
  display_name = var.agent_name
  project      = var.project_id
  region       = var.region

  spec {
    agent_framework = "google-adk"
    identity_type   = "AGENT_IDENTITY"

    container_spec {
      image_uri = "\${var.region}-docker.pkg.dev/\${var.project_id}/\${var.repository_name}/\${var.agent_name}:\${var.image_tag}"
    }

    deployment_spec {
      min_instances         = 1
      max_instances         = 4
      container_concurrency = 9
      env {
        name  = "MODEL"
        value = var.model_name
      }
      env {
        name  = "IMAGE_TAG"
        value = var.image_tag
      }
    }
  }
}`
        },
        {
            filename: "cloudbuild.yaml",
            language: "yaml",
            code: `steps:
  - id: "terraform-foundation"
    name: "hashicorp/terraform:1.9"
    dir: "terraform/foundation"
    entrypoint: "sh"
    args:
      - "-c"
      - |
        terraform init -backend-config="bucket=\${PROJECT_ID}-terraform-state" -backend-config="prefix=agent-demo/foundation"
        terraform apply -auto-approve -var="project_id=\${PROJECT_ID}" -var="region=\${_REGION}"

  - id: "build-and-push-agent"
    name: "gcr.io/cloud-builders/docker"
    args: ["build", "-t", "\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPO_NAME}/\${_AGENT_NAME}:\${_IMAGE_TAG}", "."]

  - id: "terraform-runtime-apply"
    name: "hashicorp/terraform:1.9"
    dir: "terraform/runtime"
    entrypoint: "sh"
    args:
      - "-c"
      - |
        terraform init -backend-config="bucket=\${PROJECT_ID}-terraform-state" -backend-config="prefix=agent-demo/runtime"
        terraform apply -auto-approve -var="project_id=\${PROJECT_ID}" -var="region=\${_REGION}" -var="image_tag=\${_IMAGE_TAG}"`
        }
    ],
    links: [
        {
            label: "Day 17 Demo Repository (Terraform + Cloud Build)",
            url: "https://github.com/chjoyce/advent-of-agents-s3-terraform-day17",
            description: "Quickstart demo provisioning foundation infrastructure and a single ADK agent on Vertex AI Agent Runtime via Terraform and Cloud Build."
        },
        {
            label: "Provision Agents with Terraform (Official Docs)",
            url: "https://docs.cloud.google.com/gemini-enterprise-agent-platform/scale/runtime/use-terraform",
            description: "Official guide for managing Vertex AI Agent Runtime (google_vertex_ai_reasoning_engine) declaratively with Terraform."
        }
    ],
    description: `
**Day 17 of Google's Advent of Agents — Season 3**

Deploying agents manually from a developer laptop leads to configuration drift, missing IAM bindings, and unrepeatable rollouts. By combining **Terraform** with **Google Cloud Build**, every commit packages an immutable container image and reconciles your agent's cloud infrastructure declaratively.

**How It Works**

- **Two-Stage Remote State in GCS**: Foundation resources (\`terraform/foundation\` — Artifact Registry, least-privilege IAM, VPC network, and Model Armor safety templates) are isolated from the agent runtime lifecycle (\`terraform/runtime\` — \`google_vertex_ai_reasoning_engine\`).
- **Cryptographic Agent Identity**: Provisioning with \`identity_type = "AGENT_IDENTITY"\` assigns a managed W3C / SPIFFE identity to the agent container automatically.
- **Automated Cloud Build Handoff**: \`cloudbuild.yaml\` builds and pushes the ADK container image with an immutable tag (\`_IMAGE_TAG\`) and passes it directly into \`terraform apply\`.
`,
    videoURL: "https://www.youtube.com/embed/PLACEHOLDER"
};
