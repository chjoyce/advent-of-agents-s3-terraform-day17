# Advent of Agents — Season 3, Day 17: Terraform & Cloud Build Agent Deployment

> **"Our policies forbid manual console clicks and local workstation CLIs in production. How do we automate agent deployment?"**

Prototyping with `agents-cli` is great for speed, but production demands reproducible **Infrastructure as Code (IaC)**. This repository demonstrates a two-stage **Terraform** (`terraform/foundation` and `terraform/runtime`) and **Cloud Build** (`cloudbuild.yaml`) pipeline that packages a **Google ADK** conversational agent and declaratively provisions its entire production security stack—**Vertex AI Agent Runtime**, **SPIFFE Agent Identity**, **Ingress & Egress Agent Gateways**, **Model Armor** prompt/response screening, **Network Security Authz Extensions & Policies**, and **IAM**—ready to test interactively in the **Vertex AI Agent Engine Playground**.

---

## 🏛️ Architecture & Repository Structure

```text
User / Vertex AI Playground
       │
       ▼
┌──────────────────────────────┐
│    Ingress Agent Gateway     │  ◄── Model Armor Authz Policy (CONTENT_AUTHZ: Prompt & Response templates)
│      (CLIENT_TO_AGENT)       │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│   Vertex AI Agent Runtime    │  ◄── ADK Conversational Agent (`agent/agent.py` + `agent/server.py`)
│ (SPIFFE: AGENT_IDENTITY)     │      + Session & Streaming class_methods for Playground
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│     Egress Agent Gateway     │  ◄── Egress Allow Policy (REQUEST_AUTHZ: ALLOW)
│     (AGENT_TO_ANYWHERE)      │      + PSC Network Attachment (`10.10.0.0/24`) & TLS Inspection CA
└──────────────────────────────┘
```

| File / Folder | Purpose |
| :--- | :--- |
| [`agent/agent.py`](agent/agent.py) | Cheerful, friendly ADK conversational agent (`root_agent = Agent(name="terraform_demo_agent", model="gemini-2.5-flash", ...)`) ready to test in the Vertex AI Playground. |
| [`agent/server.py`](agent/server.py) | FastAPI Reasoning Engine server exposing `/api/reasoning_engine` and `/api/stream_reasoning_engine` with in-memory session management. |
| [`agent/Dockerfile`](agent/Dockerfile) | Packages the ADK agent container (`uvicorn server:app --host 0.0.0.0 --port 8080`) and installs the Egress Agent Gateway TLS inspection root CA. |
| [`terraform/foundation/`](terraform/foundation/main.tf) | **Stage 1 Terraform** (GCS state: `gs://${TF_BUCKET}/agent-demo/foundation/`): Enables GCP APIs & Data Access Audit Logs, provisions Artifact Registry (`agent-images`), VPC (`agent-demo-vpc`), Subnet (`agent-demo-subnet`), Network Attachment (`agent-demo-attachment`), **Ingress & Egress Agent Gateways** (`google_network_services_agent_gateway`), **Dual Model Armor Templates** (`agent-demo-security` & `agent-demo-security-responses`), and **Authz Extension + Network Security Authz Policies**. |
| [`terraform/runtime/`](terraform/runtime/main.tf) | **Stage 2 Terraform** (GCS state: `gs://${TF_BUCKET}/agent-demo/runtime/`): Deploys `google_vertex_ai_reasoning_engine.agent` with `identity_type = "AGENT_IDENTITY"` (SPIFFE), Playground `class_methods`, `agent_gateway_config` (`client_to_agent_config` + `agent_to_anywhere_config`), and binds least-privilege IAM roles directly to `principal://${effective_identity}`. |
| [`cloudbuild.yaml`](cloudbuild.yaml) | **Main Deployment Pipeline**: Runs `terraform apply` in `terraform/foundation`, exports gateway IDs and TLS root CA certs, builds and pushes `./agent` to Artifact Registry, and runs `terraform apply` in `terraform/runtime`. |
| [`cloudbuild-pr.yaml`](cloudbuild-pr.yaml) | **Pull Request Pipeline**: Runs `terraform init`, `terraform validate`, and `terraform plan` across both stages before merge. |
| [`bootstrap.sh`](bootstrap.sh) / [`commands.txt`](commands.txt) | Automated script and copy-pasteable commands to enable APIs, create the versioned GCS state bucket, bind Cloud Build IAM roles, and initialize Terraform state. |

---

## ⚡ Option 1: 60-Second Local Validation (No Cloud Credentials Required)

Verify the Terraform HCL syntax, provider schemas, and ADK agent configuration locally:

```bash
./demo.sh
```

---

## ☁️ Option 2: Full Google Cloud Deployment (Step-by-Step Commands)

You can run `./bootstrap.sh` to execute steps 1–4 automatically, or copy-paste the commands below (also in [`commands.txt`](commands.txt)).

### 1. Set Environment Variables & Enable Required APIs

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION="us-central1"
export TF_BUCKET="${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud services enable \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  compute.googleapis.com \
  networkservices.googleapis.com \
  networksecurity.googleapis.com \
  aiplatform.googleapis.com \
  agentregistry.googleapis.com \
  modelarmor.googleapis.com
```

### 2. Create a Versioned GCS Bucket for Terraform State

```bash
gcloud storage buckets create \
  "gs://${TF_BUCKET}" \
  --location="${REGION}"

gcloud storage buckets update \
  "gs://${TF_BUCKET}" \
  --versioning
```

### 3. Persist Terraform States in Separate `/foundation` and `/runtime` Folders in GCS

```bash
terraform -chdir=terraform/foundation init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

terraform -chdir=terraform/runtime init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"
```

### 4. Grant Required IAM Roles to the Cloud Build Service Account

```bash
declare -a ROLES=(
  "roles/storage.objectAdmin"
  "roles/artifactregistry.admin"
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
  echo "Binding $ROLE to $CLOUDBUILD_SA..."
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done

echo "✅ All IAM roles successfully bound to Cloud Build Service Account!"
```

### 5. Run the Cloud Build Deployment Pipeline

```bash
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_TF_BUCKET="${TF_BUCKET}",_REGION="${REGION}"
```

---

## 🎮 Demoing the Chatbot Agent in the Vertex AI Playground

Once the Cloud Build pipeline finishes:

1. Open the Google Cloud Console and navigate to **Vertex AI $\rightarrow$ Agent Engine** (`https://console.cloud.google.com/vertex-ai/agents/agent-engines?project=${PROJECT_ID}`).
2. Click on **`terraform-demo-agent`**.
3. Open the **Playground** tab and chat with the agent directly in the Playground UI.

---

## 🧹 Cleanup

To tear down the deployed resources:

```bash
terraform -chdir=terraform/runtime destroy -auto-approve
terraform -chdir=terraform/foundation destroy -auto-approve
```
