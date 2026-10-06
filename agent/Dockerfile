FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -rf /var/lib/apt/lists/*

# Install Egress Agent Gateway TLS inspection root certificates into the
# system CA store and Python's certifi bundle when present.
COPY agw_root_certs.crt /tmp/agw_root_certs.crt
RUN if grep -q "BEGIN CERTIFICATE" /tmp/agw_root_certs.crt 2>/dev/null; then \
      awk 'BEGIN {c=0} /BEGIN CERTIFICATE/ {c++} c > 0 { print > "/usr/local/share/ca-certificates/agw-" c ".crt" }' /tmp/agw_root_certs.crt && \
      update-ca-certificates && \
      cat /tmp/agw_root_certs.crt >> "$(python3 -c 'import certifi; print(certifi.where())')"; \
    fi && \
    rm -f /tmp/agw_root_certs.crt

ENV GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

ENV GOOGLE_GENAI_USE_VERTEXAI=1
ENV GOOGLE_CLOUD_LOCATION=us-central1
ENV GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES=false
ENV GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY=false
ENV PYTHONUNBUFFERED=1

COPY agent.py /app/agent.py
COPY server.py /app/server.py

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"]
