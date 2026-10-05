#!/usr/bin/env bash
#
# Advent of Agents - Season 3 (Day 17): One-Time GCP Project Bootstrap
# Enables APIs, creates the GCS Terraform state bucket with versioning,
# binds required IAM roles to the Cloud Build Service Account, and initializes
# remote state for both terraform/foundation and terraform/runtime.
#

set -e

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
export REGION="${REGION:-us-central1}"
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")"
export TF_BUCKET="${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "======================================================================"
echo "🎃 Advent of Agents S3 (Day 17) — Bootstrapping Project: $PROJECT_ID"
echo "   Project Number: $PROJECT_NUMBER | Region: $REGION"
echo "   State Bucket:   gs://$TF_BUCKET"
echo "======================================================================"

# 1. Enable Required Google Cloud APIs
echo ">>> [1/4] Enabling Google Cloud APIs..."
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
  modelarmor.googleapis.com \
  --project="$PROJECT_ID"

# Ensure Vertex AI Service Agent identity is provisioned
gcloud beta services identity create \
  --service=aiplatform.googleapis.com \
  --project="$PROJECT_ID" >/dev/null 2>&1 || true

# 2. Create & Enable Versioning on GCS Terraform State Bucket
echo ">>> [2/4] Creating GCS Terraform state bucket (gs://${TF_BUCKET})..."
if ! gcloud storage buckets describe "gs://${TF_BUCKET}" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud storage buckets create \
    "gs://${TF_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="${REGION}"
fi

gcloud storage buckets update \
  "gs://${TF_BUCKET}" \
  --versioning

# 3. Bind Required IAM Roles to Cloud Build Service Account
echo ">>> [3/4] Binding IAM roles to Cloud Build Service Account ($CLOUDBUILD_SA)..."
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

for ROLE in "${ROLES[@]}"; do
  echo "Binding $ROLE to $CLOUDBUILD_SA..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done

echo "✅ All IAM roles successfully bound to Cloud Build Service Account!"

# 4. Initialize Remote Terraform State in GCS
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> [4/4] Initializing Terraform remote states in gs://${TF_BUCKET}..."
cd "$REPO_DIR/terraform/foundation"
terraform init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

cd "$REPO_DIR/terraform/runtime"
terraform init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"

cd "$REPO_DIR"
echo "======================================================================"
echo "✅ Bootstrap Complete! Next, deploy via Cloud Build:"
echo "   gcloud builds submit --config=cloudbuild.yaml --substitutions=_REGION=${REGION}"
echo "======================================================================"
