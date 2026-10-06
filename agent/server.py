import inspect
import json
import logging
import os
import traceback
from typing import Any, AsyncIterator

from fastapi import FastAPI, HTTPException, Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse, StreamingResponse
from google.adk.artifacts.in_memory_artifact_service import InMemoryArtifactService
from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
from google.adk.sessions.in_memory_session_service import InMemorySessionService
import google.auth
import vertexai
from vertexai import agent_engines

from agent import root_agent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("reasoning_engine_server")

# Ensure project and location are configured for Vertex AI / google-genai SDK.
# Prefer GOOGLE_CLOUD_PROJECT_ID (non-numeric project ID) so neither vertexai.init()
# nor AdkApp.project_id() attempts a gRPC Cloud Resource Manager lookup at cold start
# behind the Egress Agent Gateway (b/561814776).
project_id = os.environ.get("GOOGLE_CLOUD_PROJECT_ID") or os.environ.get(
    "GOOGLE_CLOUD_PROJECT"
)
if not project_id:
  try:
    _, project_id = google.auth.default()
  except Exception:
    project_id = None
if project_id:
  os.environ["GOOGLE_CLOUD_PROJECT"] = project_id

location = os.environ.get(
    "GOOGLE_CLOUD_AGENT_ENGINE_LOCATION",
    os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1"),
)
os.environ["GOOGLE_CLOUD_LOCATION"] = location
os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "1"
os.environ.setdefault("GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY", "false")

if project_id:
  vertexai.init(project=project_id, location=location)

session_service = InMemorySessionService()
memory_service = InMemoryMemoryService()
artifact_service = InMemoryArtifactService()

adk_app = agent_engines.AdkApp(
    agent=root_agent,
    session_service_builder=lambda: session_service,
    memory_service_builder=lambda: memory_service,
    artifact_service_builder=lambda: artifact_service,
    instrumentor_builder=lambda *args, **kwargs: None,
    enable_tracing=False,
)
adk_app.project_id = lambda: project_id
try:
  adk_app.set_up()
except Exception as exc:
  logger.warning("Deferred AdkApp.set_up() due to startup error: %s", exc)

app = FastAPI(title="ADK Reasoning Engine Server")


async def _ensure_session(user_id: str, session_id: str | None) -> None:
  """Ensures that a session with the given session_id exists in memory."""
  if not session_id:
    return
  existing = await session_service.get_session(
      app_name=adk_app._app_name(),
      user_id=user_id,
      session_id=session_id,
  )
  if not existing:
    await session_service.create_session(
        app_name=adk_app._app_name(),
        user_id=user_id,
        session_id=session_id,
    )


@app.get("/")
@app.get("/health")
async def health():
  return {"status": "ok"}


@app.post("/api/reasoning_engine", response_class=JSONResponse)
async def handle_query(request: Request):
  raw_body = await request.body()
  try:
    body = json.loads(raw_body.decode("utf-8")) if raw_body else {}
  except Exception as exc:
    logger.error("Invalid JSON on /api/reasoning_engine: %s", exc)
    raise HTTPException(status_code=400, detail=f"Invalid JSON: {exc}") from exc

  class_method = body.get("class_method") or "query"
  params: dict[str, Any] = dict(body.get("input") or {})
  print(
      f"[ReasoningEngine] POST /api/reasoning_engine class_method={class_method}"
      f" keys={list(params.keys())}",
      flush=True,
  )

  try:
    if class_method in ("get_session", "async_get_session"):
      user_id = params.get("user_id", "default_user")
      session_id = params.get("session_id")
      await _ensure_session(user_id=user_id, session_id=session_id)
      output = await adk_app.async_get_session(**params)
    elif class_method in ("list_sessions", "async_list_sessions"):
      output = await adk_app.async_list_sessions(**params)
    elif class_method in ("create_session", "async_create_session"):
      output = await adk_app.async_create_session(**params)
    elif class_method in ("delete_session", "async_delete_session"):
      output = await adk_app.async_delete_session(**params)
    elif class_method in (
        "query",
        "async_query",
        "stream_query",
        "async_stream_query",
    ):
      user_id = params.setdefault("user_id", "default_user")
      await _ensure_session(
          user_id=user_id, session_id=params.get("session_id")
      )
      events = []
      async for event in adk_app.async_stream_query(**params):
        events.append(event)
      output = events
    else:
      method = getattr(adk_app, class_method, None)
      if method is None:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported class_method: {class_method}",
        )
      if inspect.iscoroutinefunction(method):
        output = await method(**params)
      else:
        output = method(**params)

    return JSONResponse(content=jsonable_encoder({"output": output}))
  except HTTPException:
    raise
  except Exception as exc:
    traceback.print_exc()
    raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/api/stream_reasoning_engine", response_class=StreamingResponse)
async def handle_stream_query(request: Request):
  raw_body = await request.body()
  try:
    body = json.loads(raw_body.decode("utf-8")) if raw_body else {}
  except Exception as exc:
    logger.error("Invalid JSON on /api/stream_reasoning_engine: %s", exc)
    raise HTTPException(status_code=400, detail=f"Invalid JSON: {exc}") from exc

  class_method = body.get("class_method") or "async_stream_query"
  params: dict[str, Any] = dict(body.get("input") or {})
  print(
      "[ReasoningEngine] POST /api/stream_reasoning_engine"
      f" class_method={class_method} keys={list(params.keys())}",
      flush=True,
  )

  async def _stream() -> AsyncIterator[str]:
    try:
      if class_method == "streaming_agent_run_with_events":
        async for chunk in adk_app.streaming_agent_run_with_events(**params):
          yield f"{json.dumps(jsonable_encoder(chunk))}\n"
      else:
        user_id = params.setdefault("user_id", "default_user")
        await _ensure_session(
            user_id=user_id, session_id=params.get("session_id")
        )
        async for chunk in adk_app.async_stream_query(**params):
          yield f"{json.dumps(jsonable_encoder(chunk))}\n"
    except Exception as exc:
      traceback.print_exc()
      error_chunk = {
          "error": str(exc),
          "content": {
              "role": "model",
              "parts": [{"text": f"Error executing agent: {exc}"}],
          },
      }
      yield f"{json.dumps(error_chunk)}\n"

  return StreamingResponse(_stream(), media_type="application/json")
