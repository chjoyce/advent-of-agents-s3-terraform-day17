# Day 17: Deploy an ADK Agent with Terraform and Cloud Build

Deploy a containerized Google ADK agent to Vertex AI Agent Engine using a two-stage Terraform pipeline (`terraform/foundation` and `terraform/runtime`) and Cloud Build, governed by Ingress and Egress Agent Gateways, Model Armor, and SPIFFE (`AGENT_IDENTITY`).

## Architecture

```text
Vertex AI Playground
       │
       ▼
Ingress Agent Gateway (CLIENT_TO_AGENT)  + Model Armor (CONTENT_AUTHZ)
       │
       ▼
Vertex AI Agent Runtime (AGENT_IDENTITY) + ADK Agent (agent/agent.py, agent/server.py)
       │
       ▼
Egress Agent Gateway (AGENT_TO_ANYWHERE) + PSC Attachment & TLS Inspection CA
```

### Repository Layout

- `agent/` — ADK agent (`agent.py`), FastAPI Reasoning Engine server (`server.py`), and `Dockerfile`.
- `terraform/foundation/` — Stage 1: APIs, audit logs, Artifact Registry, VPC/subnet/PSC attachment, Ingress & Egress Agent Gateways, Model Armor templates, and Authz policies.
- `terraform/runtime/` — Stage 2: Vertex AI Reasoning Engine (`identity_type = "AGENT_IDENTITY"`), gateway bindings, and SPIFFE principal IAM.
- `cloudbuild.yaml` — Applies `foundation`, builds & pushes `./agent`, and applies `runtime`.
- `cloudbuild-pr.yaml` — Runs `terraform validate` and `terraform plan` for pull requests.
- `bootstrap.sh` / `commands.txt` — One-time project bootstrap commands.

---

## Walkthrough

### 1. Set Variables and Enable APIs

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

### 2. Create the Terraform State Bucket

```bash
gcloud storage buckets create "gs://${TF_BUCKET}" --location="${REGION}"
gcloud storage buckets update "gs://${TF_BUCKET}" --versioning
```

### 3. Initialize Terraform Backends

```bash
terraform -chdir=terraform/foundation init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

terraform -chdir=terraform/runtime init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"
```

### 4. Grant IAM Roles to Cloud Build

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
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done
```

### 5. Run the Cloud Build Pipeline

```bash
gcloud builds submit \
  --config=cloudbuild.yaml \
  --substitutions=_TF_BUCKET="${TF_BUCKET}",_REGION="${REGION}"
```

### 6. Test in the Playground

1. Open **Vertex AI > Agent Engine** in the Cloud Console.
2. Select **`terraform-demo-agent`** and open the **Playground** tab.
3. Send a test prompt to verify responses through the Ingress and Egress Agent Gateways.

---

## Service Agent & Runtime IAM (Managed by Terraform)

In addition to the Cloud Build roles in Step 4, Terraform binds the following service-agent and workload roles automatically:

| Principal | Roles | Purpose |
| :--- | :--- | :--- |
| `service-${PROJECT_NUMBER}@gcp-sa-aiplatform.iam.gserviceaccount.com` | `roles/networkservices.admin`, `roles/aiplatform.user` | Verify and attach `agent_gateway_config` during deployment. |
| `service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com` | `roles/artifactregistry.reader`, `roles/networkservices.admin`, `roles/aiplatform.user` | Pull the agent image from Artifact Registry and attach gateways. |
| `service-${PROJECT_NUMBER}@gcp-sa-dep.iam.gserviceaccount.com` | `roles/modelarmor.user`, `roles/modelarmor.calloutUser`, `roles/serviceusage.serviceUsageConsumer`, `roles/compute.networkUser`, `roles/dns.peer` | Execute inline Model Armor `AuthzExtension` callouts and attach to the PSC network. |
| `principal://${effective_identity}` (SPIFFE `AGENT_IDENTITY`) | `roles/aiplatform.user`, `roles/serviceusage.serviceUsageConsumer`, `roles/logging.logWriter`, `roles/monitoring.metricWriter` | Allow the agent container to call Gemini (`gemini-2.5-flash`) and write logs/metrics. |

### Implementation Notes

- **Egress Gateway TLS & Default-Deny**: `AGENT_TO_ANYWHERE` gateways default to deny and intercept TLS. `terraform/foundation` adds a `REQUEST_AUTHZ` `ALLOW` policy, and `cloudbuild.yaml` exports `egress_gateway_root_certificates` into `agent/agw_root_certs.crt` so `agent/Dockerfile` installs the proxy CA into `/etc/ssl/certs/ca-certificates.crt` and `certifi`.
- **Reserved Env Vars**: `GOOGLE_CLOUD_PROJECT` is reserved by Agent Engine (which sets it to the numeric project number). `terraform/runtime` passes `GOOGLE_CLOUD_PROJECT_ID` instead so `server.py` avoids a cold-start Cloud Resource Manager gRPC lookup behind the Egress Gateway.
- **SPIFFE Token Sharing**: `GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES="false"` is set on the runtime container so `google-auth` allows outbound Vertex AI calls with the SPIFFE workload identity.

---

## Teardown

```bash
terraform -chdir=terraform/runtime destroy -auto-approve
terraform -chdir=terraform/foundation destroy -auto-approve
```
