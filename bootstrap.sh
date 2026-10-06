#!/usr/bin/env bash
# ==============================================================================
# Day 17 — Bootstrap GCP Project, Remote Terraform State & Cloud Build IAM
# ==============================================================================
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "❌ Error: PROJECT_ID is not set. Run 'gcloud config set project YOUR_PROJECT_ID' first."
  exit 1
fi

export REGION="${REGION:-us-central1}"
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
export TF_BUCKET="${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "=================================================================="
echo "🚀 Bootstrapping Day 17 Terraform + Cloud Build Agent Demo"
echo "   PROJECT_ID     : ${PROJECT_ID}"
echo "   PROJECT_NUMBER : ${PROJECT_NUMBER}"
echo "   REGION         : ${REGION}"
echo "   TF_BUCKET      : gs://${TF_BUCKET} (agent-demo/foundation & agent-demo/runtime)"
echo "   CLOUDBUILD_SA  : ${CLOUDBUILD_SA}"
echo "=================================================================="

echo ""
echo "1️⃣  Enabling required Google Cloud APIs..."
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
  modelarmor.googleapis.com \
  --project="${PROJECT_ID}"

echo ""
echo "2️⃣  Creating versioned GCS bucket for Terraform remote state..."
if ! gcloud storage buckets describe "gs://${TF_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create \
    "gs://${TF_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}"
else
  echo "   Bucket gs://${TF_BUCKET} already exists."
fi

gcloud storage buckets update \
  "gs://${TF_BUCKET}" \
  --versioning

echo ""
echo "3️⃣  Binding required IAM roles to Cloud Build Service Account (${CLOUDBUILD_SA})..."
declare -a ROLES=(
  "roles/logging.logWriter"
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
  echo "   Binding $ROLE to $CLOUDBUILD_SA..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --no-user-output-enabled
done

echo "✅ All IAM roles successfully bound to Cloud Build Service Account!"

echo ""
echo "4️⃣  Initializing Terraform remote state in GCS (agent-demo/foundation & agent-demo/runtime)..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

terraform -chdir="${ROOT_DIR}/terraform/foundation" init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

terraform -chdir="${ROOT_DIR}/terraform/runtime" init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"

echo ""
echo "🎉 Bootstrap complete! Run the Cloud Build deployment pipeline with:"
echo "   gcloud builds submit --config=cloudbuild.yaml --substitutions=_TF_BUCKET=${TF_BUCKET},_REGION=${REGION}"
