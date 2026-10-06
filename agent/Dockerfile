FROM python:3.11-slim

WORKDIR /app

ENV GOOGLE_GENAI_USE_VERTEXAI=1
ENV GOOGLE_CLOUD_LOCATION=us-central1
ENV GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES=false

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent.py /app/agents/demo_agent/agent.py

CMD ["adk", "api_server", "--host=0.0.0.0", "--port=8080", "--session_service_uri=memory://", "--gemini_enterprise_app_name=demo_agent", "/app/agents"]


