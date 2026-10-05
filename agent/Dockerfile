FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent.py .

CMD ["adk", "api_server", "--host", "0.0.0.0", "--port", "8080", "."]
