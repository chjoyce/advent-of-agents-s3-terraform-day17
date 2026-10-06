# Automate Production Agent Deployment with Terraform & Cloud Build

> **Google's Advent of Agents — Season 3 (Day 17)**  
> Deploy a Google ADK agent to Google Cloud Agent Platform using a two-stage Terraform and Cloud Build pipeline, protected by Agent Gateway and Model Armor.

---

## How It Works

Instead of putting everything into one giant Terraform file, this project splits infrastructure into **two stages** (stored in separate folders in the same GCS state bucket) and automates them with **Cloud Build** (`cloudbuild.yaml`):

```text
User / Agent Playground
       │
       ▼
┌──────────────────────────────┐
│    Ingress Agent Gateway     │  ◄── Model Armor (screens prompts & responses)
│      (CLIENT_TO_AGENT)       │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│        Agent Runtime         │  ◄── ADK Agent (`agent/agent.py` + `agent/server.py`)
│  (SPIFFE: AGENT_IDENTITY)    │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│     Egress Agent Gateway     │  ◄── Private Service Connect (PSC) + Outbound Allow Policy
│     (AGENT_TO_ANYWHERE)      │
└──────────────────────────────┘
```

### 1. Stage 1 — `terraform/foundation` (Network & Security)
Provisions the shared infrastructure that rarely changes:
- **APIs & Audit Logs**: Enables the required Google Cloud APIs and turns on Vertex AI Data Access audit logs.
- **Service Agents & IAM**: Creates the Google-managed service agents for Vertex AI and Service Extensions, granting them permission to verify gateways, pull images, and call Model Armor.
- **Artifact Registry**: Creates a Docker repository (`agent-images`) to store your agent container.
- **Networking**: Creates a VPC (`agent-demo-vpc`), subnet (`10.10.0.0/24`), and Private Service Connect (PSC) network attachment (`agent-demo-attachment`).
- **Agent Gateways**: Creates the **Ingress Gateway** (`agent-demo-ingress` for incoming requests) and **Egress Gateway** (`agent-demo-egress` for outbound calls).
- **Model Armor & Policies**: Creates prompt and response safety templates (`agent-demo-security` and `agent-demo-security-responses`) and attaches them to the Ingress Gateway.

### 2. Container Build — `cloudbuild.yaml` (Steps 2 & 3)
Packages your Python ADK agent (`agent/`):
- Exports the gateway IDs and the Egress Gateway's TLS certificate from Stage 1.
- Builds the Docker container (`agent/Dockerfile`) and pushes it to Artifact Registry.

### 3. Stage 2 — `terraform/runtime` (Agent Deployment)
Deploys the agent container and runs on every code update:
- **Agent Runtime**: Deploys `terraform-demo-agent` using the new container image and connects it to the Ingress and Egress Gateways from Stage 1.
- **Agent Identity (`AGENT_IDENTITY`)**: Assigns the agent its own cryptographic SPIFFE identity (`principal://...`) and grants it permissions to call Gemini (`roles/aiplatform.user`) and write logs (`roles/logging.logWriter`).

---

## Quickstart (Google Cloud Shell)

Clone the repository and open the project directory:

```bash
git clone https://github.com/chjoyce/advent-of-agents-s3-terraform-day17.git
cd advent-of-agents-s3-terraform-day17
```

### Step 1: Set Variables & Enable APIs

Set your project variables and enable the Google Cloud APIs used by the pipeline:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION="us-central1"
export TF_BUCKET="${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

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
```

### Step 2: Create the Terraform State Bucket

Create a versioned Cloud Storage bucket to store Terraform state for both stages:

```bash
gcloud storage buckets create "gs://${TF_BUCKET}" --location="${REGION}"
gcloud storage buckets update "gs://${TF_BUCKET}" --versioning
```

### Step 3: Initialize Terraform State Folders

Initialize the `foundation` and `runtime` folders so each stage tracks its state in a separate GCS prefix:

```bash
terraform -chdir=terraform/foundation init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

terraform -chdir=terraform/runtime init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"
```

### Step 4: Grant Permissions to Cloud Build

Grant the Cloud Build service account permission to provision the network, gateways, Model Armor templates, and Agent Runtime:

```bash
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
  echo "Binding $ROLE..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done
```

### Step 5: Deploy with Cloud Build

Trigger the Cloud Build pipeline to run Stage 1 (`foundation`), build and push the agent image, and run Stage 2 (`runtime`):

```bash
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_TF_BUCKET="${TF_BUCKET}",_REGION="${REGION}"
```

---

## Test Your Agent in the Playground

1. In the Google Cloud Console, go to **Agent Platform → Agents → Deployments**.
2. Click on **`terraform-demo-agent`**.
3. Open the **Playground** tab and send a message to chat with your agent.

---

## Cleanup

To delete the deployed resources when you are finished:

```bash
terraform -chdir=terraform/runtime destroy -auto-approve \
  -var="project_id=${PROJECT_ID}" \
  -var="project_number=${PROJECT_NUMBER}" \
  -var="ingress_gateway_id=unused" \
  -var="egress_gateway_id=unused"

terraform -chdir=terraform/foundation destroy -auto-approve \
  -var="project_id=${PROJECT_ID}"
```
