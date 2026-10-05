import inspect
import json
import os
from typing import Any, AsyncIterator

from fastapi import FastAPI, HTTPException, encoders, responses
from google.adk.agents import Agent
from pydantic import BaseModel
from starlette.concurrency import iterate_in_threadpool, run_in_threadpool
import uvicorn
from vertexai.agent_engines import AdkApp


# ==============================================================================
# 1. DEFINE OUR SINGLE ADK AGENT & TOOLS
# ==============================================================================
def get_spooky_forecast(city: str) -> dict[str, str]:
    """Returns the Halloween weather and trick-or-treat candy forecast for a city.

    Args:
        city: The name of the city (e.g., "Seattle", "San Francisco").
    """
    return {
        "city": city,
        "temperature": "56°F (Chilly & Eerie)",
        "fog_level": "Heavy Haunted Mist 🌫️",
        "recommended_treat": "Full-Size Peanut Butter Cups 🍬",
        "vibe": "10/10 Spooky",
    }


def check_deployment_status(environment: str = "production") -> dict[str, str]:
    """Returns the current Terraform + Cloud Build deployment metadata of the agent.

    Args:
        environment: Target environment name (default: "production").
    """
    return {
        "environment": environment,
        "framework": "Google ADK (google-adk)",
        "provisioned_by": "Terraform (google_vertex_ai_reasoning_engine)",
        "built_by": "Cloud Build (cloudbuild.yaml)",
        "identity_type": "AGENT_IDENTITY (SPIFFE)",
        "model_armor_template": os.environ.get(
            "MODEL_ARMOR_TEMPLATE_ID", "agent-demo-safety-template"
        ),
        "image_tag": os.environ.get("IMAGE_TAG", "v1.0.0"),
        "status": "RESOURCE_STATE_ACTIVE 🎃",
    }


root_agent = Agent(
    name="day17_adk_ops_agent",
    model=os.environ.get("MODEL", "gemini-2.5-flash"),
    description="Single ADK Ops & Weather Agent provisioned via Terraform and deployed by Cloud Build.",
    instruction=(
        "You are the Day 17 Advent of Agents Ops Assistant! 🎃 "
        "Use `get_spooky_forecast` when asked about weather or trick-or-treating in a city, "
        "and use `check_deployment_status` when asked how you were built, deployed, governed, or provisioned. "
        "Keep your responses concise, helpful, and lightly Halloween-themed!"
    ),
    tools=[get_spooky_forecast, check_deployment_status],
)

# Wrap the ADK Agent in Vertex AI Agent Engine's AdkApp template
adk_app = AdkApp(agent=root_agent)


# ==============================================================================
# 2. EXPOSE THE VERTEX AI AGENT RUNTIME CONTRACT (:8080)
# ==============================================================================
app = FastAPI(title="Advent of Agents S3 Day 17 — Terraform ADK Runtime")
_is_setup = False


def _ensure_setup() -> AdkApp:
    global _is_setup
    if not _is_setup:
        adk_app.set_up()
        _is_setup = True
    return adk_app


class QueryRequest(BaseModel):
    class_method: str = "async_stream_query"
    input: dict[str, Any] | None = None


@app.get("/health")
async def health() -> dict[str, str]:
    return {
        "status": "ok",
        "agent": root_agent.name,
        "image_tag": os.environ.get("IMAGE_TAG", "v1.0.0"),
    }


@app.post("/api/reasoning_engine")
async def query_reasoning_engine(request: QueryRequest) -> responses.JSONResponse:
    """Unary endpoint for session operations (create_session, list_sessions, etc.)."""
    runtime = _ensure_setup()
    method = getattr(runtime, request.class_method, None)
    if method is None:
        raise HTTPException(
            status_code=400,
            detail=f"Method {request.class_method!r} not found on AdkApp.",
        )

    kwargs = request.input or {}
    if inspect.iscoroutinefunction(method):
        output = await method(**kwargs)
    else:
        output = await run_in_threadpool(method, **kwargs)

    return responses.JSONResponse(
        content=encoders.jsonable_encoder({"output": output})
    )


@app.post("/api/stream_reasoning_engine")
async def stream_reasoning_engine(
    request: QueryRequest,
) -> responses.StreamingResponse:
    """Streaming endpoint for :streamQuery (async_stream_query, stream_query)."""
    runtime = _ensure_setup()
    method = getattr(runtime, request.class_method, None)
    if method is None:
        raise HTTPException(
            status_code=400,
            detail=f"Streaming method {request.class_method!r} not found on AdkApp.",
        )

    kwargs = request.input or {}
    stream = (
        await method(**kwargs)
        if inspect.iscoroutinefunction(method)
        else method(**kwargs)
    )

    async def _ndjson_stream() -> AsyncIterator[str]:
        if hasattr(stream, "__aiter__"):
            async for chunk in stream:
                yield json.dumps(encoders.jsonable_encoder(chunk)) + "\n"
        else:
            async for chunk in iterate_in_threadpool(stream):
                yield json.dumps(encoders.jsonable_encoder(chunk)) + "\n"

    return responses.StreamingResponse(
        content=_ndjson_stream(),
        media_type="application/json",
    )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
