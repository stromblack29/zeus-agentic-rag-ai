import { NextRequest, NextResponse } from "next/server";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

function buildFastAPIBody(body: Record<string, any>) {
  return JSON.stringify({
    session_id: body.sessionId ?? body.session_id,
    message: body.message,
    image_base64: body.imageBase64 ?? body.image_base64 ?? null,
    llm_model: body.llmModel ?? body.llm_model ?? "gemini-2.5-flash",
  });
}

// ── Streaming POST (/api/chat  with stream:true in body) ──────────────────────
// Proxies FastAPI SSE → browser as ReadableStream (text/event-stream)
async function handleStream(body: Record<string, any>): Promise<Response> {
  const fastapiRes = await fetch(`${FASTAPI_URL}/api/chat/stream`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: buildFastAPIBody(body),
  });

  if (!fastapiRes.ok || !fastapiRes.body) {
    const errText = await fastapiRes.text();
    return NextResponse.json(
      { error: `FastAPI stream error: ${errText}` },
      { status: fastapiRes.status },
    );
  }

  // Pipe the upstream SSE directly to the client
  const { readable, writable } = new TransformStream();
  fastapiRes.body.pipeTo(writable);

  return new Response(readable, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "X-Accel-Buffering": "no",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

// ── Non-streaming POST (standard JSON for Postman / fallback) ─────────────────
async function handleJSON(body: Record<string, any>): Promise<Response> {
  const fastapiRes = await fetch(`${FASTAPI_URL}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: buildFastAPIBody(body),
  });

  if (!fastapiRes.ok) {
    const errText = await fastapiRes.text();
    return NextResponse.json(
      { error: `FastAPI error: ${errText}` },
      { status: fastapiRes.status },
    );
  }

  const data = await fastapiRes.json();
  return NextResponse.json({
    reply: data.reply,
    session_id: data.session_id,
    model_used: data.model_used,
  });
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    if (body.stream === true) {
      return handleStream(body);
    }
    return handleJSON(body);
  } catch (e: any) {
    return NextResponse.json(
      { error: e.message ?? "Unknown error" },
      { status: 500 },
    );
  }
}
