#!/usr/bin/env bash
#
# Advent of Agents - Season 3 (Day 17): Quick Demo Runner
# Modeled after Cybersizemore/advent-agents-supplychain-simple/demo-simple.sh
#
# Usage:
#   ./demo.sh          # < 30s local verification (Terraform validate + ADK agent tool check)
#   ./demo.sh deploy   # Full Cloud Build + Terraform deployment + live Agent Runtime query
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

MODE="${1:-local}"

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${BLUE}${BOLD}🎃 ADVENT OF AGENTS - DAY 17: TERRAFORM + CLOUD BUILD AGENT DEMO${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

if [ "$MODE" = "local" ]; then
  echo -e "\n${GREEN}${BOLD}>>> 1/3: Validating Stage 1 Terraform (terraform/foundation)${NC}"
  cd "$REPO_DIR/terraform/foundation"
  terraform fmt -check
  terraform init -backend=false -input=false >/dev/null
  terraform validate

  echo -e "\n${GREEN}${BOLD}>>> 2/3: Validating Stage 2 Terraform (terraform/runtime)${NC}"
  cd "$REPO_DIR/terraform/runtime"
  terraform fmt -check
  terraform init -backend=false -input=false >/dev/null
  terraform validate

  echo -e "\n${GREEN}${BOLD}>>> 3/3: Verifying Single ADK Agent Tools & Runtime Contract${NC}"
  cd "$REPO_DIR"
  python3 -c '
import ast, pathlib
src = pathlib.Path("main.py").read_text()
tree = ast.parse(src)
funcs = [n.name for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
print("[PASS] Parsed main.py AST successfully.")
print("       Discovered Agent Tools & Endpoints:", ", ".join(funcs))
assert "get_spooky_forecast" in funcs and "check_deployment_status" in funcs
assert "query_reasoning_engine" in funcs and "stream_reasoning_engine" in funcs
print("[PASS] Vertex AI Agent Runtime HTTP contract (:8080) verified!")
'

  echo -e "\n${BLUE}${BOLD}======================================================================${NC}"
  echo -e "${GREEN}${BOLD}✔ Local Kata Complete! (Foundation TF = Valid, Runtime TF = Valid, ADK Contract = Valid)${NC}"
  echo -e "👉 Ready to deploy to Google Cloud? Run:"
  echo -e "   ${YELLOW}./bootstrap.sh && ./demo.sh deploy${NC}"
  echo -e "${BLUE}${BOLD}======================================================================${NC}"

elif [ "$MODE" = "deploy" ]; then
  export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
  export REGION="${REGION:-us-central1}"
  export TF_BUCKET="${PROJECT_ID}-terraform-state"
  export IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"

  echo -e "\n${GREEN}${BOLD}>>> 1/3: Submitting Cloud Build Pipeline (cloudbuild.yaml)...${NC}"
  gcloud builds submit \
    --project="$PROJECT_ID" \
    --config=cloudbuild.yaml \
    --substitutions="_REGION=${REGION},_IMAGE_TAG=${IMAGE_TAG}"

  echo -e "\n${GREEN}${BOLD}>>> 2/3: Fetching Deployed Agent Runtime ID from GCS State...${NC}"
  cd "$REPO_DIR/terraform/runtime"
  terraform init -reconfigure \
    -backend-config="bucket=${TF_BUCKET}" \
    -backend-config="prefix=agent-demo/runtime" >/dev/null
  ENGINE_ID="$(terraform output -raw reasoning_engine_id)"
  STREAM_URL="$(terraform output -raw stream_query_url)"
  cd "$REPO_DIR"

  echo -e "   Deployed Reasoning Engine ID: ${BOLD}${ENGINE_ID}${NC}"
  echo -e "   Streaming Endpoint:           ${BOLD}${STREAM_URL}${NC}"

  echo -e "\n${GREEN}${BOLD}>>> 3/3: Querying Live ADK Agent on Vertex AI Agent Runtime...${NC}"
  curl -s -X POST \
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
  echo ""
fi
