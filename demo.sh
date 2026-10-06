#!/usr/bin/env bash
# ==============================================================================
# Day 17 — 60-Second Local Validation Demo (No Cloud Credentials Required)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo "🏗️  Advent of Agents S3 (Day 17) — Local Terraform + ADK Validation"
echo "=================================================================="

echo ""
echo "🔍 [Step 1/3] Validating Stage 1: terraform/foundation (VPC, Agent Gateways, Model Armor & Authz Policies)..."
cd "${ROOT_DIR}/terraform/foundation"
terraform fmt -check
terraform init -backend=false -input=false >/dev/null
terraform validate
rm -f .terraform/terraform.tfstate

echo ""
echo "🔍 [Step 2/3] Validating Stage 2: terraform/runtime (Vertex AI Agent Runtime + SPIFFE Identity + Gateway Routing)..."
cd "${ROOT_DIR}/terraform/runtime"
terraform fmt -check
terraform init -backend=false -input=false >/dev/null
terraform validate
rm -f .terraform/terraform.tfstate

echo ""
echo "🔍 [Step 3/3] Verifying ADK Chatbot Agent Definition (agent/agent.py, agent/server.py & agent/Dockerfile)..."
cd "${ROOT_DIR}"
python3 - << 'PYEOF'
import ast
from pathlib import Path

agent_src = Path("agent/agent.py").read_text()
server_src = Path("agent/server.py").read_text()
dockerfile = Path("agent/Dockerfile").read_text()

ast.parse(agent_src)
ast.parse(server_src)

assert "root_agent" in agent_src, "Missing root_agent definition in agent/agent.py"
assert "/api/reasoning_engine" in server_src and "/api/stream_reasoning_engine" in server_src, "Missing Reasoning Engine routes in agent/server.py"
assert "uvicorn" in dockerfile and "8080" in dockerfile, "Missing uvicorn entrypoint in agent/Dockerfile"
print("   ✅ agent/agent.py defines 'root_agent' (terraform_demo_agent)")
print("   ✅ agent/server.py & agent/Dockerfile expose Reasoning Engine server on 0.0.0.0:8080")
PYEOF

echo ""
echo "=================================================================="
echo "✅ ALL CHECKS PASSED!"
echo "   Ready to deploy to Google Cloud via ./bootstrap.sh and Cloud Build."
echo "=================================================================="
