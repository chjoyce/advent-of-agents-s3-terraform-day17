# Advent of Agents — Season 3, Day 17: Terraform & Cloud Build Agent Deployment

> **"Our policies forbid manual console clicks and local workstation CLIs in production. How do we automate agent deployment?"**

Prototyping with `agents-cli` is great for speed, but production demands reproducible **Infrastructure as Code (IaC)**. This repository demonstrates a two-stage **Terraform** (`terraform/foundation` and `terraform/runtime`) and **Cloud Build** (`cloudbuild.yaml`) pipeline that packages a simple **Google ADK** chatbot agent and declaratively provisions its entire production security stack—**Vertex AI Agent Runtime**, **SPIFFE Agent Identity**, **Ingress & Egress Agent Gateways**, **Model Armor** prompt/response screening, **Network Security Authz Extensions & Policies**, and **IAM**—ready to test interactively in the **Vertex AI Agent Engine Playground**.

---

## 🏛️ Architecture & Repository Structure

```text
User / Vertex AI Playground
       │
       ▼
┌──────────────────────────────┐
│    Ingress Agent Gateway     │  ◄── Model Armor Authz Policy (CONTENT_AUTHZ: Prompt Injection, PII, RAI)
│      (CLIENT_TO_AGENT)       │      + IAP Authz Policy (REQUEST_AUTHZ: DRY_RUN audit logging)
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│   Vertex AI Agent Runtime    │  ◄── ADK Chatbot Agent (`agent/agent.py`)
│ (SPIFFE: AGENT_IDENTITY)     │      + Session & Streaming class_methods for Playground
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│     Egress Agent Gateway     │  ◄── Model Armor Authz Policy (CONTENT_AUTHZ: Request + Response templates)
│     (AGENT_TO_ANYWHERE)      │      + PSC Network Attachment (`10.10.0.0/24` + `240.0.0.0/4` VIP firewall)
└──────────────────────────────┘
```

| File / Folder | Purpose |
| :--- | :--- |
| [`agent/agent.py`](agent/agent.py) | Simple ADK chatbot (`root_agent = Agent(name="terraform_demo_agent", model="gemini-2.5-flash", ...)`) ready to test in the Vertex AI Playground. |
| [`agent/Dockerfile`](agent/Dockerfile) | Packages the ADK agent container running `adk api_server --host 0.0.0.0 --port 8080 .`. |
| [`terraform/foundation/`](terraform/foundation/main.tf) | **Stage 1 Terraform**: Enables GCP APIs & Data Access Audit Logs, provisions Artifact Registry (`agent-images`), VPC (`agent-demo-vpc`), Subnet (`agent-demo-subnet`), PSC Egress VIP firewall (`240.0.0.0/4`), Network Attachment (`agent-demo-attachment`), **Ingress & Egress Agent Gateways** (`google_network_services_agent_gateway`), **Dual Model Armor Templates** (`agent-demo-security` & `agent-demo-security-responses`), and **Authz Extensions + Network Security Authz Policies** (`CONTENT_AUTHZ` + `REQUEST_AUTHZ`). |
| [`terraform/runtime/`](terraform/runtime/main.tf) | **Stage 2 Terraform**: Provisions Vertex AI Service Identities (`gcp-sa-aiplatform`, `gcp-sa-aiplatform-re`), binds least-privilege IAM (`roles/networkservices.admin`, `roles/artifactregistry.reader`), and deploys `google_vertex_ai_reasoning_engine.agent` with `identity_type = "AGENT_IDENTITY"` (SPIFFE), Playground `class_methods`, and `agent_gateway_config` (`client_to_agent_config` + `agent_to_anywhere_config`). |
| [`cloudbuild.yaml`](cloudbuild.yaml) | **Main Merge Pipeline**: Runs `terraform apply` in `terraform/foundation`, builds and pushes `./agent` to Artifact Registry, and runs `terraform apply` in `terraform/runtime`. |
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

You can run `./bootstrap.sh` to execute steps 1–5 automatically, or run the exact commands below (also in [`commands.txt`](commands.txt)).

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

### 3. Persist Terraform States in GCS

Initialize remote state for both the `foundation` and `runtime` stages:

```bash
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

### 4. Grant Required IAM Roles to the Cloud Build Service Account

```bash
# 1. Set your variables
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
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
  "roles/networksecurity.admin"
  "roles/aiplatform.admin"
  "roles/modelarmor.admin"
)

# 3. Loop through and apply bindings
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

Trigger Cloud Build to apply `terraform/foundation`, build & push the `./agent` container image to Artifact Registry, and apply `terraform/runtime`:

```bash
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_REGION="${REGION}",_TF_BUCKET="${TF_BUCKET}",_IMAGE_TAG="v1"
```

---

## 🎮 Demoing the Chatbot Agent in the Vertex AI Playground

Once the Cloud Build pipeline finishes:

1. Open the Google Cloud Console and navigate to **Vertex AI $\rightarrow$ Agent Engine** (`https://console.cloud.google.com/vertex-ai/agents/agent-engines?project=${PROJECT_ID}`).
2. Click on **`terraform-demo-agent`**.
3. Open the **Playground** tab:
   - Because `terraform/runtime/main.tf` registers the ADK session & streaming `class_methods` (`create_session`, `list_sessions`, `stream_query`, `streaming_agent_run_with_events`), you can create a session and chat with the agent directly in the Playground UI.
   - All client-to-agent and agent-to-anywhere traffic is governed by **`agent-demo-ingress`** and **`agent-demo-egress`** (`google_network_services_agent_gateway`) with **Model Armor** `CONTENT_AUTHZ` policies (`agent-demo-ma-ingress-policy` and `agent-demo-ma-egress-policy`).

---

## 🧹 Cleanup

To tear down the deployed resources:

```bash
cd terraform/runtime
terraform destroy -auto-approve

cd ../foundation
terraform destroy -auto-approve
```
