# Infrastructure as Code & Production CI/CD: Terraform + Cloud Build Agent Demo

> **Google's Advent of Agents — Season 3 (Day 17)**  
> Minimal, copy-pasteable demo showing how to provision foundation infrastructure (**Artifact Registry**, **VPC**, **Model Armor**, **Least-Privilege IAM**) and deploy a single **ADK Agent** to **Vertex AI Agent Runtime** (`google_vertex_ai_reasoning_engine`) using **Terraform** and **Cloud Build**.

---

## ⚡ Quickstart

### Option A: 30-Second Local Validation (No Cloud Resources Required)

Clone the repository and validate the Terraform modules (`foundation` + `runtime`) and the ADK Agent Runtime HTTP contract locally:

```bash
git clone https://github.com/chjoyce/advent-of-agents-s3-terraform-day17.git
cd advent-of-agents-s3-terraform-day17
./demo.sh
```

### Option B: Full End-to-End Cloud Build + Terraform Deployment

Run the automated bootstrap and deployment scripts:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

./bootstrap.sh
./demo.sh deploy
```

---

## 🛠️ Step-by-Step Commands (Manual Walkthrough)

If you prefer to run each step interactively during a live demo, copy and paste the blocks below.

### 1. Set Your Environment Variables & Enable APIs

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
export REGION="us-central1"

gcloud services enable \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  compute.googleapis.com \
  networkservices.googleapis.com \
  networksecurity.googleapis.com \
  aiplatform.googleapis.com \
  agentregistry.googleapis.com \
  modelarmor.googleapis.com
```

### 2. Create the GCS Bucket for Terraform Remote State

```bash
export TF_BUCKET="${PROJECT_ID}-terraform-state"

gcloud storage buckets create \
  "gs://${TF_BUCKET}" \
  --location="${REGION}"

gcloud storage buckets update \
  "gs://${TF_BUCKET}" \
  --versioning
```

### 3. Grant Required IAM Roles to the Cloud Build Service Account

```bash
# 1. Set your variables
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 2. List of roles required for Cloud Build & Terraform Agent Deployment
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
  "roles/serviceusage.serviceUsageAdmin"
)

# 3. Loop through and apply bindings
for ROLE in "${ROLES[@]}"; do
  echo "Binding $ROLE to $CLOUDBUILD_SA..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done

echo "✅ All IAM roles successfully bound to Cloud Build Service Account!"
```

### 4. Persist & Initialize Terraform States in GCS (`foundation` & `runtime`)

```bash
## PERSIST TERRAFORM STATES IN GCS
cd terraform/foundation

terraform init \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

cd ../runtime

terraform init \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"

cd ../..
```

### 5. Deploy via Cloud Build (`cloudbuild.yaml`)

Trigger the automated pipeline to:
1. Apply `terraform/foundation` (Artifact Registry, IAM, VPC Network, Model Armor Template)
2. Build & push the single ADK agent container image (`day17-adk-ops-agent:v1.0.0`)
3. Apply `terraform/runtime` to deploy the agent onto **Vertex AI Agent Runtime** with `AGENT_IDENTITY` (SPIFFE)

```bash
# Optional: Simulate a Pull Request dry-run first (runs docker build + terraform plan only)
gcloud builds submit \
  --config=cloudbuild-pr.yaml \
  --substitutions=_REGION="${REGION}",_IMAGE_TAG="pr-preview"

# Run the production deployment pipeline (docker build/push + terraform apply)
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_REGION="${REGION}",_IMAGE_TAG="v1.0.0"
```

### 6. Query the Deployed ADK Agent on Vertex AI Agent Runtime

```bash
# Fetch the Reasoning Engine ID and Streaming URL from remote state
cd terraform/runtime
export ENGINE_ID=$(terraform output -raw reasoning_engine_id)
export STREAM_URL=$(terraform output -raw stream_query_url)
cd ../..

echo "Deployed Agent Runtime ID: $ENGINE_ID"

# Send a live streaming query to the deployed agent
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{
    "class_method": "async_stream_query",
    "input": {
      "user_id": "day17_demo_user",
      "message": "What is the spooky forecast in Seattle and how were you provisioned?"
    }
  }' \
  "$STREAM_URL"
```

### 7. Clean Up Resources (`terraform destroy`)

```bash
cd terraform/runtime
terraform destroy -auto-approve \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}"

cd ../foundation
terraform destroy -auto-approve \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}"
cd ../..
```

---

## 📂 Structure

```text
├── content/season3/day17.ts        # Advent of Agents Season 3 (Day 17) submission file
├── terraform/
│   ├── foundation/                 # Stage 1: Base Infrastructure (prefix=agent-demo/foundation)
│   │   ├── backend.tf              # GCS remote state backend & Google providers
│   │   ├── main.tf                 # Artifact Registry, Service Accounts/IAM, VPC, Model Armor Template
│   │   ├── outputs.tf              # Foundation outputs (Repo URI, Model Armor ID, SA email)
│   │   └── variables.tf            # Foundation input variables
│   └── runtime/                    # Stage 2: Single Agent Runtime (prefix=agent-demo/runtime)
│       ├── backend.tf              # GCS remote state backend & Google providers
│       ├── main.tf                 # google_vertex_ai_reasoning_engine (ADK container + AGENT_IDENTITY)
│       ├── outputs.tf              # Deployed Reasoning Engine ID, SPIFFE identity & stream URL
│       └── variables.tf            # Runtime input variables (image_tag, model_name, etc.)
├── Dockerfile                      # ADK Agent Runtime container image definition (:8080)
├── bootstrap.sh                    # One-step script for APIs, GCS state bucket, IAM, & terraform init
├── cloudbuild-pr.yaml              # Pull Request CI pipeline (docker build + terraform plan dry-run)
├── cloudbuild.yaml                 # Main branch CD pipeline (foundation + docker push + runtime apply)
├── demo.sh                         # Quick local validator (<30s) & cloud deployment runner
├── main.py                         # Single ADK Agent + FastAPI Agent Runtime HTTP contract
└── requirements.txt                # Python dependencies (google-adk, google-cloud-aiplatform, fastapi)
```
