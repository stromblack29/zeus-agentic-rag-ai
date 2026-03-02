import os
import json
import logging
from contextlib import asynccontextmanager
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, AsyncGenerator
import uuid

from langchain_core.messages import HumanMessage
from database import get_supabase_client
from agent import create_agent_executor, build_chat_history, build_human_input

logger = logging.getLogger("zeus")

# ── Pydantic Models ────────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    session_id: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        description="UUID string identifying the chat session",
    )
    message: str = Field(..., description="User's text message")
    image_base64: Optional[str] = Field(
        default=None,
        description="Optional base64-encoded JPEG/PNG image",
    )
    llm_model: Optional[str] = Field(
        default="gemini-2.5-flash",
        description="Select LLM model: 'gemini-2.5-flash', 'gemma-3-27b', 'ollama', or 'openrouter'",
    )


class ChatResponse(BaseModel):
    session_id: str
    reply: str
    model_used: str


# ── App Lifespan ───────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Instead of creating one executor, we will create them per-request based on the model
    yield


app = FastAPI(
    title="Zeus AI Insurance Service",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Helper: Persist messages to Supabase ─────────────────────────────────────

def _save_message(session_id: str, role: str, message: str) -> None:
    client = get_supabase_client()
    client.table("chat_sessions").insert(
        {"session_id": session_id, "role": role, "message": message}
    ).execute()


def _fetch_history(session_id: str, limit: int = 20) -> list[dict]:
    client = get_supabase_client()
    response = (
        client.table("chat_sessions")
        .select("role, message")
        .eq("session_id", session_id)
        .order("created_at", desc=False)
        .limit(limit)
        .execute()
    )
    return response.data or []


# ── Endpoint ──────────────────────────────────────────────────────────────────

@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    try:
        raw_history = _fetch_history(request.session_id)
        chat_history = build_chat_history(raw_history)

        human_input = build_human_input(request.message, request.image_base64)

        # Create agent executor on the fly with the requested model
        agent_executor = create_agent_executor(model_choice=request.llm_model)

        messages = chat_history + [HumanMessage(content=human_input)]
        result = await agent_executor.ainvoke({"messages": messages})

        last_message = result["messages"][-1]
        raw_content = last_message.content if hasattr(last_message, "content") else str(last_message)
        
        if isinstance(raw_content, list):
            # Extract text from multimodal response list
            text_parts = [item["text"] for item in raw_content if isinstance(item, dict) and "text" in item]
            ai_reply = "\n".join(text_parts) if text_parts else str(raw_content)
        else:
            ai_reply = str(raw_content)

        _save_message(request.session_id, "user", request.message)
        _save_message(request.session_id, "ai", ai_reply)

        return ChatResponse(
            session_id=request.session_id, 
            reply=ai_reply,
            model_used=request.llm_model
        )

    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


async def _stream_agent_response(request: ChatRequest) -> AsyncGenerator[str, None]:
    """Generator that yields SSE-formatted chunks from the agent."""
    raw_history = _fetch_history(request.session_id)
    chat_history = build_chat_history(raw_history)
    human_input = build_human_input(request.message, request.image_base64)
    agent_executor = create_agent_executor(model_choice=request.llm_model)
    messages = chat_history + [HumanMessage(content=human_input)]

    full_reply = []
    try:
        async for event in agent_executor.astream_events({"messages": messages}, version="v2"):
            kind = event.get("event")
            # Stream only final AI text tokens (not tool calls)
            if kind == "on_chat_model_stream":
                chunk = event.get("data", {}).get("chunk")
                if chunk:
                    content = chunk.content
                    if isinstance(content, list):
                        for part in content:
                            if isinstance(part, dict) and part.get("type") == "text":
                                text = part["text"]
                                full_reply.append(text)
                                yield f"data: {json.dumps({'token': text})}\n\n"
                    elif isinstance(content, str) and content:
                        full_reply.append(content)
                        yield f"data: {json.dumps({'token': content})}\n\n"
            elif kind == "on_tool_start":
                tool_name = event.get("name", "tool")
                yield f"data: {json.dumps({'tool_start': tool_name})}\n\n"
            elif kind == "on_tool_end":
                tool_name = event.get("name", "tool")
                yield f"data: {json.dumps({'tool_end': tool_name})}\n\n"
    except Exception as exc:
        logger.error("Streaming error: %s", exc)
        yield f"data: {json.dumps({'error': str(exc)})}\n\n"
        return

    ai_reply = "".join(full_reply)
    if ai_reply:
        _save_message(request.session_id, "user", request.message)
        _save_message(request.session_id, "ai", ai_reply)

    yield f"data: {json.dumps({'done': True, 'session_id': request.session_id, 'model_used': request.llm_model})}\n\n"


@app.post("/api/chat/stream")
async def chat_stream(request: ChatRequest):
    """Streaming endpoint — returns Server-Sent Events (SSE).
    Each event is a JSON object:
      - { "token": "..." }         — partial AI text
      - { "tool_start": "name" }   — tool being called
      - { "tool_end": "name" }     — tool finished
      - { "error": "..." }         — error occurred
      - { "done": true, "session_id": ..., "model_used": ... } — final event
    """
    return StreamingResponse(
        _stream_agent_response(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/health")
async def health():
    return {"status": "ok", "service": "zeus-ai-service"}
