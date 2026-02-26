import os
from contextlib import asynccontextmanager
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Optional
import uuid

from langchain_core.messages import HumanMessage
from database import get_supabase_client
from agent import create_agent_executor, build_chat_history, build_human_input

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


class ChatResponse(BaseModel):
    session_id: str
    reply: str


# ── App Lifespan ───────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.agent_executor = create_agent_executor()
    yield


app = FastAPI(
    title="Zeus AI Insurance Service",
    version="1.0.0",
    lifespan=lifespan,
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

        agent_executor: object = app.state.agent_executor

        messages = chat_history + [HumanMessage(content=human_input)]
        result = await agent_executor.ainvoke({"messages": messages})

        last_message = result["messages"][-1]
        ai_reply: str = last_message.content if hasattr(last_message, "content") else str(last_message)

        _save_message(request.session_id, "user", request.message)
        _save_message(request.session_id, "ai", ai_reply)

        return ChatResponse(session_id=request.session_id, reply=ai_reply)

    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get("/health")
async def health():
    return {"status": "ok", "service": "zeus-ai-service"}
