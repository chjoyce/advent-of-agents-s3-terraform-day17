# Automate Production Agent Deployment with Terraform & Cloud Build

> **Google's Advent of Agents — Season 3 (Day 17)**  
> Minimal, copy-pasteable two-stage Terraform (`terraform/foundation` and `terraform/runtime`) and Cloud Build pipeline to deploy a containerized ADK agent behind Agent Gateway and Model Armor.

## What Terraform Provisions

The deployment is split into two Terraform stages with separate remote state prefixes in Cloud Storage (`agent-demo/foundation` and `agent-demo/runtime`), orchestrated end-to-end by `cloudbuild.yaml`:

### Stage 1: `terraform/foundation` (Network, Gateways & Security Policy)
1. **APIs & Audit Logs** — Enables required Google Cloud APIs and configures Vertex AI Data Access audit logs (`DATA_READ` and `DATA_WRITE`).
2. **Service Agents & IAM** — Provisions the Vertex AI (`gcp-sa-aiplatform`, `gcp-sa-aiplatform-re`) and Service Extensions (`gcp-sa-dep`) service agents and grants permissions for gateway verification, image pulls, and inline Model Armor callouts (`roles/modelarmor.user`, `roles/modelarmor.calloutUser`, `roles/serviceusage.serviceUsageConsumer`).
3. **Artifact Registry** — Creates the `agent-images` Docker repository.
4. **VPC & PSC Network Attachment** — Creates `agent-demo-vpc`, `agent-demo-subnet` (`10.10.0.0/24`), and `agent-demo-attachment` (`ACCEPT_AUTOMATIC`).
5. **Ingress & Egress Agent Gateways** — Provisions `agent-demo-ingress` (`CLIENT_TO_AGENT`) and `agent-demo-egress` (`AGENT_TO_ANYWHERE`, bound to the PSC network attachment).
6. **Model Armor & Authz Policies** — Creates prompt (`agent-demo-security`) and response (`agent-demo-security-responses`) screening templates, attaches the Model Armor `AuthzExtension` + `CONTENT_AUTHZ` policy to the Ingress Gateway, and attaches a `REQUEST_AUTHZ` `ALLOW` policy to the Egress Gateway.

### Container Build (`cloudbuild.yaml`)
- Exports `ingress_gateway_id`, `egress_gateway_id`, and `egress_gateway_root_certificates` from Stage 1, installs the Egress Gateway TLS inspection CA into the `./agent` image (`Dockerfile`), and pushes `demo-agent:${BUILD_ID}` to Artifact Registry.

### Stage 2: `terraform/runtime` (Agent Engine & SPIFFE Identity)
1. **Vertex AI Reasoning Engine** — Deploys `terraform-demo-agent` from the container image pushed by Cloud Build, registers ADK session/streaming `class_methods` for the Vertex AI Playground, and binds `agent_gateway_config` (`client_to_agent_config` + `agent_to_anywhere_config`).
2. **SPIFFE Agent Identity (`AGENT_IDENTITY`)** — Mints a per-agent cryptographic identity (`principal://agents.global.org-...`) and binds least-privilege runtime roles (`roles/aiplatform.user`, `roles/serviceusage.serviceUsageConsumer`, `roles/logging.logWriter`, `roles/monitoring.metricWriter`) so the agent can call Gemini (`gemini-2.5-flash`) and emit logs.

---

## Quickstart

Clone the repository and run the deployment in Cloud Shell:

```bash
git clone https://github.com/chjoyce/advent-of-agents-s3-terraform-day17.git
cd advent-of-agents-s3-terraform-day17
```

```bash
# 1. Set project variables
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION="us-central1"
export TF_BUCKET="${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 2. Enable required APIs
gcloud services enable \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  compute.googleapis.com \
  networkservices.googleapis.com \
  networksecurity.googleapis.com \
  aiplatform.googleapis.com \
  agentregistry.googleapis.com \
  modelarmor.googleapis.com

# 3. Create versioned GCS bucket and initialize Terraform state
gcloud storage buckets create "gs://${TF_BUCKET}" --location="${REGION}"
gcloud storage buckets update "gs://${TF_BUCKET}" --versioning

terraform -chdir=terraform/foundation init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

terraform -chdir=terraform/runtime init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"

# 4. Grant IAM roles to the Cloud Build service account
declare -a ROLES=(
  "roles/storage.objectAdmin"
  "roles/artifactregistry.admin"
  "roles/serviceusage.serviceUsageAdmin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountUser"
  "roles/compute.networkAdmin"
  "roles/networkservices.admin"
  "roles/networksecurity.admin"
  "roles/aiplatform.admin"
  "roles/modelarmor.admin"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done

# 5. Deploy foundation, build container, and deploy agent runtime
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_TF_BUCKET="${TF_BUCKET}",_REGION="${REGION}"
```

## Verify & Cleanup

Open **Vertex AI > Agent Engine** in the Cloud Console, select **`terraform-demo-agent`**, and test the agent in the **Playground** tab.

To tear down all resources:

```bash
terraform -chdir=terraform/runtime destroy -auto-approve
terraform -chdir=terraform/foundation destroy -auto-approve
```
