# Zeus Insurance AI

A full-stack AI-powered car insurance assistant for the Thai market, built with **Next.js 15**, **FastAPI**, **LangGraph**, and **Supabase**.

---

## Architecture

```
┌─────────────────────────────────┐
│   zeus-web-chat (Next.js 15)    │  ← Browser UI  (port 3000)
│   • Zeus-branded chat UI        │
│   • Streaming SSE consumer      │
│   • Model selector              │
│   • Image upload (base64)       │
│   • Session management (UUID)   │
└────────────┬────────────────────┘
             │  POST /api/chat  (proxy)
             ▼
┌─────────────────────────────────┐
│   zeus-ai-service (FastAPI)     │  ← AI Backend  (port 8000)
│   • LangGraph ReAct agent       │
│   • POST /api/chat  (JSON)      │
│   • POST /api/chat/stream (SSE) │
│   • Multi-LLM support           │
│   • CORS enabled                │
└────────────┬────────────────────┘
             │  pgvector + CRUD
             ▼
┌─────────────────────────────────┐
│   Supabase (PostgreSQL)         │
│   • car_brands / car_models     │
│   • insurance_plans / premiums  │
│   • policy_documents (RAG)      │
│   • quotations / orders         │
│   • chat_sessions               │
└─────────────────────────────────┘
```

---

## Features

### AI Agent (LangGraph ReAct)
The agent uses a **tool-calling loop** to answer insurance questions accurately:

| Tool | Purpose |
|---|---|
| `search_quotation_details` | Look up car models, plans, and premium pricing |
| `search_policy_documents` | Semantic RAG search over policy documents |
| `create_quotation` | Generate an official quotation with a QUO number |
| `create_order` | Initiate a purchase order with payment instructions |
| `get_order_status` | Check payment and policy activation status |
| `update_order_payment` | Confirm payment (admin function) |

### Database (V3 — 100+ vehicles, 65+ RAG documents)
- **20 car brands**: Honda, Toyota, Mazda, Isuzu, Mitsubishi, Nissan, Ford, Chevrolet, MG, BYD, GWM, Tesla, BMW, Mercedes-Benz, Audi, Porsche, Volvo, Subaru, Suzuki, Hyundai
- **100+ vehicle models**: 2024 and 2025 model years, economy to ultra-luxury
- **4 insurance plans**: Zeus Comprehensive Plus (Type 1), Zeus EV Shield (Type 1 EV), Zeus Value Protect (Type 2+), Zeus Budget Safe (Type 3+)
- **65+ RAG policy documents**: Coverage, Exclusions, Conditions, Definitions — in English and Thai

### Multi-LLM Support
| Model | Provider | Use Case |
|---|---|---|
| `gemini-2.5-flash` | Google (default) | Fast, accurate, multimodal |
| `gemma-3-27b` | Google AI Studio | Alternative Google model |
| `ollama` | Local (glm4:9b) | Offline/private |
| `openrouter` | OpenRouter (Qwen3-235B) | High-capability reasoning |

### Streaming SSE
- FastAPI streams tokens via `astream_events` as Server-Sent Events
- Next.js proxy pipes the SSE stream directly to the browser
- UI shows tokens progressively + animated tool call indicators

---

## Project Structure

```
zeus-agentic-rag-ai/
├── zeus-ai-service/          # FastAPI Python backend
│   ├── main.py               # API endpoints (/api/chat, /api/chat/stream)
│   ├── agent.py              # LangGraph ReAct agent + LLM config
│   ├── database.py           # Supabase client
│   ├── init_supabase_v2.sql  # Full DB schema + seed data
│   ├── ingest_embeddings.py  # RAG embedding ingestion script
│   ├── tools/
│   │   ├── quotation_db_tool.py
│   │   ├── policy_rag_tool.py
│   │   ├── create_quotation_tool.py
│   │   ├── create_order_tool.py
│   │   └── update_order_payment.py (via create_order_tool)
│   └── .env                  # GEMINI_API_KEY, SUPABASE_URL, etc.
│
└── zeus-web-chat/            # Next.js 15 frontend
    ├── app/
    │   ├── page.tsx           # Entry → <ZeusChatWindow />
    │   ├── layout.tsx         # Zeus-branded root layout
    │   └── api/chat/route.ts  # Proxy: stream → FastAPI SSE, JSON → FastAPI
    ├── components/
    │   ├── ZeusChatWindow.tsx # Main chat UI + streaming logic
    │   ├── ZeusMessageBubble.tsx # Markdown + quotation/order cards
    │   ├── ModelSelector.tsx  # LLM model dropdown
    │   └── ImageUploadButton.tsx # Base64 image upload
    ├── utils/
    │   ├── session.ts         # UUID session management (localStorage)
    │   └── cn.ts              # Tailwind class merge utility
    └── .env.local             # FASTAPI_URL=http://localhost:8000
```

---

## Setup

### Prerequisites
- Python 3.11+
- Node.js 18+
- Supabase project with pgvector enabled
- Google Gemini API key

### 1. Clone and configure environment

```bash
git clone https://github.com/stromblack29/zeus-agentic-rag-ai.git
cd zeus-agentic-rag-ai
```

**Backend** (`zeus-ai-service/.env`):
```env
GEMINI_API_KEY=your_gemini_api_key
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_service_role_key
OPENROUTER_API_KEY=your_openrouter_key   # optional
```

**Frontend** (`zeus-web-chat/.env.local`):
```env
FASTAPI_URL=http://localhost:8000
```

### 2. Initialize Supabase Database

1. Open your Supabase project → **SQL Editor**
2. Paste and run the full contents of `zeus-ai-service/init_supabase_v2.sql`
3. Verify tables exist:

| Table | Records |
|---|---|
| `car_brands` | 20 brands |
| `car_models` | 100+ models (2024-2025) |
| `insurance_plans` | 4 plans |
| `plan_coverages` | Coverage limits |
| `plan_premiums` | Premium matrix |
| `policy_documents` | 65+ RAG docs (embeddings NULL initially) |
| `quotations` | Empty (created by AI) |
| `orders` | Empty (created by AI) |
| `chat_sessions` | Empty (populated on use) |

### 3. Ingest RAG Embeddings

```bash
cd zeus-ai-service
pip install -r requirements.txt

# Embed all new documents (default — skips already-embedded)
python ingest_embeddings.py

# Force re-embed everything
python ingest_embeddings.py --force

# Embed only new Coverage documents
python ingest_embeddings.py --section Coverage
```

### 4. Start FastAPI backend

```bash
cd zeus-ai-service
python -m uvicorn main:app --reload --port 8000
```

API docs available at: `http://localhost:8000/docs`

### 5. Start Next.js frontend

```bash
cd zeus-web-chat
npm install
npm run dev
```

Open: `http://localhost:3000`

---

## API Reference

### POST `/api/chat` — JSON (Postman-friendly)

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "message": "Honda Civic e:HEV RS 2024 ประกันชั้น 1 เท่าไร?",
  "image_base64": null,
  "llm_model": "gemini-2.5-flash"
}
```

**Response:**
```json
{
  "session_id": "550e8400-...",
  "reply": "สำหรับ Honda Civic e:HEV RS 2024 ประกันชั้น 1...",
  "model_used": "gemini-2.5-flash"
}
```

### POST `/api/chat/stream` — Server-Sent Events

Same request body as above. Returns `text/event-stream`:

```
data: {"token": "สำหรับ"}
data: {"token": " Honda"}
data: {"tool_start": "search_quotation_details"}
data: {"tool_end": "search_quotation_details"}
data: {"token": " Civic..."}
data: {"done": true, "session_id": "...", "model_used": "gemini-2.5-flash"}
```

### GET `/health`
```json
{"status": "ok", "service": "zeus-ai-service"}
```

---

## Complete Order Workflow Example

```
User: ต้องการประกันรถ Honda Civic e:HEV RS 2024
  → Agent calls search_quotation_details(brand="Honda", model="Civic", sub_model="e:HEV RS")
  → Agent calls search_policy_documents(query="Type 1 coverage")
  → Agent presents 3 plan options with premiums

User: เลือกแผน Zeus Comprehensive Plus ชื่อ สมชาย อีเมล test@example.com
  → Agent calls create_quotation(car_model_id=2, plan_id=1, customer_name="สมชาย", ...)
  → Returns: QUO-20240301-0001, valid 30 days, premium 25,000 THB

User: ต้องการซื้อเลย จ่ายด้วย PromptPay
  → Agent calls create_order(quotation_id="...", payment_method="promptpay")
  → Returns: ORD-20240301-0001, PromptPay QR, policy number POL-20240301-0001

User: ชำระเงินแล้ว
  → Agent calls get_order_status(order_number="ORD-20240301-0001")
  → Returns current payment_status and policy_status
```

---

## Testing with curl / Postman

### JSON endpoint (non-streaming)
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test-001",
    "message": "ประกันชั้น 1 Honda Civic e:HEV RS 2024 เท่าไร?",
    "llm_model": "gemini-2.5-flash"
  }'
```

### SSE streaming endpoint
```bash
curl -N -X POST http://localhost:8000/api/chat/stream \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test-001",
    "message": "แนะนำประกันสำหรับ Tesla Model Y 2024",
    "llm_model": "gemini-2.5-flash"
  }'
```

### Next.js proxy (streaming, from browser/Postman)
```bash
curl -N -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "test-001",
    "message": "BYD Seal ประกันชั้น 1 ราคาเท่าไร?",
    "llmModel": "gemini-2.5-flash",
    "stream": true
  }'
```

> **Postman tip:** For SSE, set the request to POST, add `stream: true` in the JSON body, and check the response in the **Console** tab (not Body) to see tokens arrive in real time.

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Embeddings missing | Run `python ingest_embeddings.py`; check `VECTOR(2000)` column exists |
| LLM not splitting brand/model | Check `agent.py` system prompt for split instructions |
| CORS error from browser | Confirm `allow_origins` in `main.py` includes `http://localhost:3000` |
| OpenRouter not responding | Verify `OPENROUTER_API_KEY` in `.env` |
| Streaming shows no tokens | Check FastAPI logs; ensure `astream_events` version is `v2` |
| Next.js build fails | Run `npm run build` in `zeus-web-chat/`; check for missing packages |
