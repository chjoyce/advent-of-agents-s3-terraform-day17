FROM python:3.11-slim

WORKDIR /app

# Install system CA certificates and, when deployed behind an Egress Agent Gateway
# (AGENT_TO_ANYWHERE), install the gateway's TLS inspection root certificates.
COPY agw_root_certs.crt /tmp/agw_root_certs.crt
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    if grep -q "BEGIN CERTIFICATE" /tmp/agw_root_certs.crt 2>/dev/null; then \
      awk 'BEGIN {c=0} /BEGIN CERTIFICATE/ {c++} c > 0 { print > "/usr/local/share/ca-certificates/agw-" c ".crt" }' /tmp/agw_root_certs.crt && \
      update-ca-certificates; \
    fi && \
    rm -f /tmp/agw_root_certs.crt && \
    rm -rf /var/lib/apt/lists/*

ENV GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV AGENT_GATEWAY_ROOT_CERT_302034098528=/etc/ssl/certs/ca-certificates.crt

ENV GOOGLE_GENAI_USE_VERTEXAI=1
ENV GOOGLE_CLOUD_LOCATION=us-central1
ENV GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES=false
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent.py /app/agent.py
COPY agent.py /app/agents/demo_agent/agent.py
COPY server.py /app/server.py

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"]
