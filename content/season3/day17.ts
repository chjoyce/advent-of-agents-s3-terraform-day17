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
      filename: "terraform/runtime/main.tf",
      language: "hcl",
      code: `# Persisted in GCS via: terraform init -backend-config="bucket=\${TF_BUCKET}" -backend-config="prefix=agent-demo/runtime"
terraform {
  backend "gcs" {}
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.25.0"
    }
  }
}

# Read foundational outputs (Artifact Registry, VPC, Model Armor, Service Account) from GCS state
data "terraform_remote_state" "foundation" {
  backend = "gcs"
  config = {
    bucket = "\${var.project_id}-terraform-state"
    prefix = "agent-demo/foundation"
  }
}

# Provision Vertex AI Agent Runtime with cryptographic SPIFFE identity & Model Armor
resource "google_vertex_ai_reasoning_engine" "agent" {
  provider     = google-beta
  project      = var.project_id
  region       = var.region
  display_name = "day17-governed-adk-agent"

  spec {
    agent_framework = "google-adk"
    identity_type   = "AGENT_IDENTITY" # Mints cryptographic SPIFFE ID
    service_account = data.terraform_remote_state.foundation.outputs.agent_service_account_email

    container_spec {
      image_uri = var.image_uri # Built & pushed to Artifact Registry by Cloud Build
    }

    deployment_spec {
      env {
        name  = "GEMINI_MODEL"
        value = "gemini-3.1-flash-lite"
      }
      env {
        name  = "MODEL_ARMOR_TEMPLATE_ID"
        value = data.terraform_remote_state.foundation.outputs.model_armor_template_id
      }
    }
  }
}`
    },
    {
      filename: "cloudbuild.yaml",
      language: "yaml",
      code: `steps:
  # 1. Foundation: Apply APIs, Artifact Registry, VPC, Model Armor & IAM backed by GCS state
  - id: "terraform-foundation"
    name: "hashicorp/terraform:1.9"
    dir: "terraform/foundation"
    entrypoint: "sh"
    args:
      - "-c"
      - |
        terraform init -backend-config="bucket=\${_TF_BUCKET}" -backend-config="prefix=agent-demo/foundation"
        terraform plan -var="project_id=\${PROJECT_ID}" -var="region=\${_REGION}" -out=tfplan
        terraform apply -auto-approve tfplan

  # 2. Build the agent: Package container image and push to Artifact Registry
  - id: "build-and-push-agent"
    name: "gcr.io/cloud-builders/docker"
    args:
      - "build"
      - "-t"
      - "\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/agent-repo/adk-agent:\${SHORT_SHA}"
      - "--push"
      - "."

  # 3. Provision & deploy: Update Agent Runtime with the newly built container image
  - id: "terraform-runtime"
    name: "hashicorp/terraform:1.9"
    dir: "terraform/runtime"
    entrypoint: "sh"
    args:
      - "-c"
      - |
        terraform init -backend-config="bucket=\${_TF_BUCKET}" -backend-config="prefix=agent-demo/runtime"
        terraform plan \\
          -var="project_id=\${PROJECT_ID}" \\
          -var="region=\${_REGION}" \\
          -var="image_uri=\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/agent-repo/adk-agent:\${SHORT_SHA}" \\
          -out=tfplan
        terraform apply -auto-approve tfplan

substitutions:
  _REGION: "us-central1"
  _TF_BUCKET: "\${PROJECT_ID}-terraform-state"`
    },
    {
      filename: "bootstrap.sh",
      language: "bash",
      code: `export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
export REGION="us-central1"
export TF_BUCKET="\${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="\${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 1. Enable required Google Cloud APIs
gcloud services enable \\
  cloudbuild.googleapis.com cloudresourcemanager.googleapis.com \\
  artifactregistry.googleapis.com iam.googleapis.com compute.googleapis.com \\
  networkservices.googleapis.com networksecurity.googleapis.com \\
  aiplatform.googleapis.com agentregistry.googleapis.com modelarmor.googleapis.com

# 2. Create versioned Cloud Storage bucket for remote Terraform state
gcloud storage buckets create "gs://\${TF_BUCKET}" --location="\${REGION}"
gcloud storage buckets update "gs://\${TF_BUCKET}" --versioning

# 3. Grant Cloud Build Service Account permissions to provision infra & deploy agents
declare -a ROLES=(
  "roles/storage.objectAdmin"
  "roles/artifactregistry.admin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountUser"
  "roles/compute.networkAdmin"
  "roles/networkservices.admin"
  "roles/aiplatform.admin"
  "roles/modelarmor.admin"
)
for ROLE in "\${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \\
    --member="serviceAccount:$CLOUDBUILD_SA" --role="$ROLE" --no-user-output-enabled
done

# 4. Trigger the Cloud Build CI/CD pipeline
gcloud builds submit --config=cloudbuild.yaml \\
  --substitutions=_REGION="\${REGION}",_TF_BUCKET="\${TF_BUCKET}" .`
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
