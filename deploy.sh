#!/usr/bin/env bash
# ==============================================================================
# Day 17 — End-to-End Setup & Cloud Build Deployment (Steps 1–5)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set. Run 'gcloud config set project YOUR_PROJECT_ID' first."
  exit 1
fi

export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
export REGION="${REGION:-us-central1}"
export TF_BUCKET="${PROJECT_ID}-terraform-state"
export CLOUDBUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "=================================================================="
echo "Deploying Day 17 Terraform + Cloud Build Agent Demo"
echo "  PROJECT_ID     : ${PROJECT_ID}"
echo "  PROJECT_NUMBER : ${PROJECT_NUMBER}"
echo "  REGION         : ${REGION}"
echo "  TF_BUCKET      : gs://${TF_BUCKET}"
echo "  CLOUDBUILD_SA  : ${CLOUDBUILD_SA}"
echo "=================================================================="

echo ""
echo "[Step 1/5] Enabling required Google Cloud APIs..."
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
echo "[Step 2/5] Creating versioned GCS bucket for Terraform remote state..."
if ! gcloud storage buckets describe "gs://${TF_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}"
else
  echo "Bucket gs://${TF_BUCKET} already exists."
fi

gcloud storage buckets update "gs://${TF_BUCKET}" --versioning --project="${PROJECT_ID}"

echo ""
echo "[Step 3/5] Initializing Terraform state folders in GCS..."
terraform -chdir="${ROOT_DIR}/terraform/foundation" init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/foundation"

terraform -chdir="${ROOT_DIR}/terraform/runtime" init -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=agent-demo/runtime"

echo ""
echo "[Step 4/5] Granting IAM roles to Cloud Build Service Account (${CLOUDBUILD_SA})..."
declare -a ROLES=(
  "roles/logging.logWriter"
  "roles/storage.objectAdmin"
  "roles/serviceusage.serviceUsageAdmin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/compute.networkAdmin"
  "roles/networkservices.admin"
  "roles/artifactregistry.admin"
  "roles/modelarmor.admin"
  "roles/networksecurity.admin"
  "roles/aiplatform.admin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountUser"
)

for ROLE in "${ROLES[@]}"; do
  echo "Binding $ROLE..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CLOUDBUILD_SA" \
    --role="$ROLE" \
    --condition=None \
    --no-user-output-enabled
done

echo ""
echo "[Step 5/5] Submitting Cloud Build deployment pipeline..."
gcloud builds submit "${ROOT_DIR}" \
  --project="${PROJECT_ID}" \
  --config="${ROOT_DIR}/cloudbuild.yaml" \
  --substitutions=_TF_BUCKET="${TF_BUCKET}",_REGION="${REGION}"
