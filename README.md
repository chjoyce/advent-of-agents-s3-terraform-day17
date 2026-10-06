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
│      (CLIENT_TO_AGENT)       │      + Service Extensions P4SA (`gcp-sa-dep`) inline callout IAM
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│   Vertex AI Agent Runtime    │  ◄── ADK Conversational Agent (`agent/agent.py` + `agent/server.py`)
│ (SPIFFE: AGENT_IDENTITY)     │      + Principal IAM (`roles/aiplatform.user`, `serviceUsageConsumer`, `logWriter`)
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
| [`agent/Dockerfile`](agent/Dockerfile) | Packages the ADK agent container (`uvicorn server:app --host 0.0.0.0 --port 8080`) and installs the Egress Agent Gateway TLS inspection root CA into both the system CA store and `certifi`. |
| [`terraform/foundation/`](terraform/foundation/main.tf) | **Stage 1 Terraform** (GCS state: `gs://${TF_BUCKET}/agent-demo/foundation/`): Enables GCP APIs & Data Access Audit Logs, pre-provisions Vertex AI & DEP Service Agents + IAM, creates Artifact Registry (`agent-images`), VPC (`agent-demo-vpc`), Subnet (`agent-demo-subnet`), Network Attachment (`agent-demo-attachment`), **Ingress & Egress Agent Gateways** (`google_network_services_agent_gateway`), **Dual Model Armor Templates** (`agent-demo-security` & `agent-demo-security-responses`), and **Authz Extension + Network Security Authz Policies**. |
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

## 🔐 Complete IAM & Service Agent Reference (Why Each Role Is Required)

Deploying an ADK agent with `identity_type = "AGENT_IDENTITY"` behind **Ingress & Egress Agent Gateways** and **Model Armor** involves **four distinct principals**. Missing any of these bindings causes deployment failures or runtime `403`/`404` errors in the Playground:

### 1. Cloud Build Service Account (`${PROJECT_NUMBER}-compute@developer.gserviceaccount.com`)
*Granted once during bootstrap (`bootstrap.sh` / Step 4 above) so Cloud Build can execute Terraform:*
- `roles/storage.objectAdmin` — Read/write remote Terraform state in `gs://${TF_BUCKET}` and stage Cloud Build source archives.
- `roles/artifactregistry.admin` — Create the `agent-images` Docker repository and push built agent images.
- `roles/serviceusage.serviceUsageAdmin` — Enable Google Cloud APIs via `google_project_service`.
- `roles/resourcemanager.projectIamAdmin` — Manage project IAM bindings (`google_project_iam_member`) and Data Access audit logs (`google_project_iam_audit_config`).
- `roles/iam.serviceAccountAdmin` & `roles/iam.serviceAccountUser` — Provision Google-managed service identities (`google_project_service_identity`).
- `roles/compute.networkAdmin` — Provision VPC, Subnet, and PSC Network Attachment.
- `roles/networkservices.admin` — Provision Ingress & Egress Agent Gateways (`google_network_services_agent_gateway`) and Authz Extensions (`google_network_services_authz_extension`).
- `roles/networksecurity.admin` — Provision `CONTENT_AUTHZ` and `REQUEST_AUTHZ` policies (`google_network_security_authz_policy`).
- `roles/aiplatform.admin` — Create and update the Vertex AI Reasoning Engine (`google_vertex_ai_reasoning_engine`).
- `roles/modelarmor.admin` — Create Model Armor prompt & response screening templates (`google_model_armor_template`).

### 2. Vertex AI Service Agents (`gcp-sa-aiplatform` & `gcp-sa-aiplatform-re`)
*Provisioned automatically by Terraform in [`terraform/foundation/main.tf`](terraform/foundation/main.tf) and [`terraform/runtime/main.tf`](terraform/runtime/main.tf):*
- **`service-${PROJECT_NUMBER}@gcp-sa-aiplatform.iam.gserviceaccount.com`**:
  - `roles/networkservices.admin` — Required so Vertex AI can verify and bind `agent_gateway_config` (`client_to_agent_config` & `agent_to_anywhere_config`) when deploying the Reasoning Engine.
  - `roles/aiplatform.user` — Standard Vertex AI control-plane access.
- **`service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com`**:
  - `roles/artifactregistry.reader` — Required so the Reasoning Engine serverless runtime can pull the custom container image from Artifact Registry.
  - `roles/networkservices.admin` & `roles/aiplatform.user` — Required for runtime gateway attachment and Vertex AI access.

### 3. Service Extensions / Data Egress Protection P4SA (`gcp-sa-dep`)
*Provisioned automatically by Terraform in [`terraform/foundation/main.tf`](terraform/foundation/main.tf) (`google_project_iam_member.dep_p4sa_roles`):*
- **`service-${PROJECT_NUMBER}@gcp-sa-dep.iam.gserviceaccount.com`**:
  - `roles/modelarmor.user` & `roles/modelarmor.calloutUser` — Required so the Ingress Agent Gateway can invoke the Model Armor `AuthzExtension` inline callout (`forward_headers = ["authorization"]`). Without these roles, the gateway blocks Playground requests with `403`/`404`.
  - `roles/serviceusage.serviceUsageConsumer` — Required for project quota validation during inline Model Armor callouts.
  - `roles/compute.networkUser` & `roles/dns.peer` — Required for Egress Agent Gateway PSC network attachment connectivity.

### 4. Agent Runtime SPIFFE Identity (`principal://agents.global.org-...`)
*Provisioned automatically by Terraform in [`terraform/runtime/main.tf`](terraform/runtime/main.tf) (`google_project_iam_member.agent_identity_roles`):*
- **`principal://${google_vertex_ai_reasoning_engine.agent.spec[0].effective_identity}`**:
  - When `identity_type = "AGENT_IDENTITY"` is enabled, the agent container runs under a dedicated cryptographic SPIFFE identity rather than a shared IAM service account.
  - `roles/aiplatform.user` & `roles/serviceusage.serviceUsageConsumer` — Required so the agent container can invoke Gemini models (`gemini-2.5-flash`) on Vertex AI. (In addition, the container sets `GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES="false"` so `google-auth` permits outbound Vertex AI calls using the SPIFFE workload token.)
  - `roles/logging.logWriter` & `roles/monitoring.metricWriter` — Required so container stdout/stderr (`aiplatform.googleapis.com/reasoning_engine_stdout` and `reasoning_engine_stderr`) and telemetry are written to Cloud Logging and Cloud Monitoring.

---

## 🛠️ Key Production Gotchas Solved in This Repo

1. **Egress Agent Gateway Default-Deny & TLS Inspection CA**:
   - Attaching an `AGENT_TO_ANYWHERE` Egress Agent Gateway enforces a default-deny posture and intercepts outbound TLS traffic using a regional proxy CA (`agent_gateway_card[0].root_certificates`).
   - [`terraform/foundation/main.tf`](terraform/foundation/main.tf) provisions `google_network_security_authz_policy.egress_allow_policy` (`REQUEST_AUTHZ` `ALLOW`), and [`cloudbuild.yaml`](cloudbuild.yaml) exports `egress_gateway_root_certificates` into `agent/agw_root_certs.crt` so [`agent/Dockerfile`](agent/Dockerfile) installs the CA into both `/etc/ssl/certs/ca-certificates.crt` (`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH`) and `certifi.where()`.
2. **Reserved Environment Variables in `spec.deployment_spec.env`**:
   - Vertex AI Agent Engine automatically injects `GOOGLE_CLOUD_PROJECT` (set to the numeric project number) and `GOOGLE_CLOUD_QUOTA_PROJECT`, and rejects deployments that specify `GOOGLE_CLOUD_PROJECT` in `spec.deployment_spec.env`.
   - [`terraform/runtime/main.tf`](terraform/runtime/main.tf) instead passes `GOOGLE_CLOUD_PROJECT_ID = var.project_id`, and [`agent/server.py`](agent/server.py) maps it into `os.environ["GOOGLE_CLOUD_PROJECT"]` at startup so `AdkApp.set_up()` never attempts a cold-start gRPC lookup to Cloud Resource Manager (`projects.get`) behind the Egress Agent Gateway.
3. **`google-adk` Package Extra Compatibility**:
   - [`agent/requirements.txt`](agent/requirements.txt) specifies `google-adk>=1.18.0` (without the deprecated `google-adk[gcp]` extra, which forced `pip` to backtrack to `google-adk==1.14.1` and fail on `Runner(..., auto_create_session=True)`).

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
