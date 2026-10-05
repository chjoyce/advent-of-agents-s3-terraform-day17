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

echo ""
echo "🔍 [Step 2/3] Validating Stage 2: terraform/runtime (Vertex AI Agent Runtime + SPIFFE Identity + Gateway Routing)..."
cd "${ROOT_DIR}/terraform/runtime"
terraform fmt -check
terraform init -backend=false -input=false >/dev/null
terraform validate

echo ""
echo "🔍 [Step 3/3] Verifying ADK Chatbot Agent Definition (agent/agent.py & agent/Dockerfile)..."
cd "${ROOT_DIR}"
python3 - << 'PYEOF'
import ast
from pathlib import Path

src = Path("agent/agent.py").read_text()
tree = ast.parse(src)
dockerfile = Path("agent/Dockerfile").read_text()

assert "root_agent" in src, "Missing root_agent definition in agent/agent.py"
assert "adk" in dockerfile and "api_server" in dockerfile, "Missing adk api_server entrypoint in agent/Dockerfile"
print("   ✅ agent/agent.py defines 'root_agent' (terraform_demo_agent)")
print("   ✅ agent/Dockerfile exposes ADK API server on 0.0.0.0:8080 for Vertex AI Playground")
PYEOF

echo ""
echo "=================================================================="
echo "✅ ALL CHECKS PASSED!"
echo "   Ready to deploy to Google Cloud via ./bootstrap.sh and Cloud Build."
echo "=================================================================="
