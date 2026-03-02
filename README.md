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

## Tech Stack: LangChain & LangGraph

Zeus AI Service is built on the **LangChain** and **LangGraph** ecosystem, providing a robust agentic framework for tool-calling, memory management, and streaming responses.

### Core Components

#### 1. **LangGraph ReAct Agent** (`langgraph.prebuilt.create_react_agent`)
The heart of Zeus is a **ReAct (Reasoning + Acting) agent** that follows a thought-action-observation loop:

```python
from langgraph.prebuilt import create_react_agent

agent_executor = create_react_agent(
    llm=llm,
    tools=[search_quotation_details, search_policy_documents, 
           create_quotation, create_order, update_order_payment, 
           get_order_status],
    prompt=SYSTEM_PROMPT
)
```

**How it works:**
1. **Reasoning**: Agent analyzes user request and decides which tool(s) to call
2. **Acting**: Executes tool calls with extracted parameters
3. **Observation**: Processes tool results and formulates response
4. **Iteration**: Repeats until task is complete or max iterations reached

#### 2. **LangChain Tool Integration** (`@tool` decorator)
All Zeus tools are LangChain-native functions using the `@tool` decorator:

```python
from langchain_core.tools import tool

@tool
def search_quotation_details(
    brand: str,
    model: str | None = None,
    sub_model: str | None = None,
    year: int | None = None
) -> str:
    """Search for car insurance quotations by vehicle details."""
    # Tool implementation with Supabase queries
    return json.dumps(results)
```

**Benefits:**
- Automatic schema generation for LLM function calling
- Type validation and error handling
- Seamless integration with LangGraph agent executor

#### 3. **Multi-LLM Support** (LangChain Chat Models)
Zeus supports multiple LLM providers through LangChain's unified chat interface:

| LangChain Class | Model | Provider |
|---|---|---|
| `ChatGoogleGenerativeAI` | `gemini-2.5-flash` | Google AI Studio (default) |
| `ChatGoogleGenerativeAI` | `gemma-3-27b-it` | Google AI Studio (fallback) |
| `ChatOllama` | `glm4:9b` | Local Ollama server |
| `ChatOpenAI` | `qwen3-235b` | OpenRouter API |

**Fallback mechanism:**
```python
primary_llm = ChatGoogleGenerativeAI(model="gemini-2.5-flash", ...)
fallback_llm = ChatGoogleGenerativeAI(model="gemma-3-27b-it", ...)
llm = primary_llm.with_fallbacks([fallback_llm])
```

#### 4. **Chat History Management** (LangChain Messages)
Conversation context is maintained using LangChain message types:

```python
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage

def build_chat_history(raw_history: list[dict]) -> list:
    messages = []
    for record in raw_history:
        if record["role"] == "user":
            messages.append(HumanMessage(content=record["message"]))
        elif record["role"] == "ai":
            messages.append(AIMessage(content=record["message"]))
    return messages
```

**Storage flow:**
1. User message → `HumanMessage` → Agent executor
2. Agent response → `AIMessage` → Supabase `chat_sessions` table
3. Next request → Fetch history → Rebuild message list → Agent executor

#### 5. **Multimodal Input** (Vision Support)
Zeus supports image analysis using LangChain's multimodal message format:

```python
def build_human_input(text_message: str, image_base64: str | None) -> list | str:
    if not image_base64:
        return text_message
    
    return [
        {
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}
        },
        {
            "type": "text",
            "text": text_message or "Please analyze this image..."
        }
    ]
```

**Use cases:**
- Upload car registration document → Extract brand/model/year
- Upload damage photos → Assess claim eligibility
- Upload policy document → Extract coverage details

#### 6. **Streaming with `astream_events`** (LangChain v2 Events)
Real-time token streaming using LangChain's event-based streaming API:

```python
async for event in agent_executor.astream_events(
    {"messages": messages},
    version="v2"
):
    if event["event"] == "on_chat_model_stream":
        # Stream LLM tokens
        token = event["data"]["chunk"].content
        yield f"data: {json.dumps({'token': token})}\n\n"
    
    elif event["event"] == "on_tool_start":
        # Notify tool execution start
        tool_name = event["name"]
        yield f"data: {json.dumps({'tool_start': tool_name})}\n\n"
    
    elif event["event"] == "on_tool_end":
        # Notify tool execution end
        tool_name = event["name"]
        yield f"data: {json.dumps({'tool_end': tool_name})}\n\n"
```

**Event types tracked:**
- `on_chat_model_stream` → Token-by-token LLM output
- `on_tool_start` → Tool execution begins
- `on_tool_end` → Tool execution completes
- `on_chain_end` → Agent execution finished

#### 7. **RAG with LangChain Embeddings**
Semantic search over policy documents using Google's embedding model:

```python
from langchain_google_genai import GoogleGenerativeAIEmbeddings

embeddings_model = GoogleGenerativeAIEmbeddings(
    model="models/text-embedding-004",
    google_api_key=os.environ["GEMINI_API_KEY"]
)

# Generate query embedding
query_embedding = embeddings_model.embed_query(query_text)

# Trim to 2000 dimensions for Supabase pgvector
trimmed_embedding = query_embedding[:2000]

# Semantic search via Supabase RPC
results = supabase.rpc(
    "match_documents",
    {
        "query_embedding": trimmed_embedding,
        "match_threshold": 0.5,
        "match_count": 5
    }
).execute()
```

**RAG pipeline:**
1. User query → `embed_query()` → 768D vector → Trim to 2000D
2. Supabase `match_documents` RPC → Cosine similarity search
3. Top-K documents → Injected into LLM context
4. LLM generates answer grounded in retrieved documents

### LangChain Dependencies

```txt
langchain              # Core abstractions (BaseMessage, BaseTool, etc.)
langchain-core         # Message types, runnables, streaming
langchain-google-genai # Gemini/Gemma chat models + embeddings
langchain-community    # Community integrations
langchain-ollama       # Local Ollama support
langchain-openai       # OpenRouter/OpenAI support
langgraph              # Agent orchestration framework
```

### Why LangChain + LangGraph?

| Feature | Benefit |
|---|---|
| **Unified LLM Interface** | Switch between Gemini, Ollama, OpenRouter without code changes |
| **Built-in Tool Calling** | Automatic function schema generation and parameter extraction |
| **Streaming Events** | Real-time token streaming + tool execution visibility |
| **Message Abstraction** | Clean separation of user/AI/system messages |
| **ReAct Agent Pattern** | Proven reasoning loop for complex multi-step tasks |
| **Fallback Handling** | Automatic failover between LLM providers |
| **Multimodal Support** | Native image + text input handling |
| **RAG Integration** | Seamless embedding generation and vector search |

### Agent Execution Flow

```
User Request
    ↓
[1] Build chat history (HumanMessage, AIMessage)
    ↓
[2] Create agent executor (LangGraph ReAct)
    ↓
[3] Agent reasoning loop:
    ├─ LLM decides: "Need to call search_quotation_details"
    ├─ Extract parameters: brand="Honda", model="Civic"
    ├─ Execute tool → Supabase query
    ├─ Observe results → 4 matching vehicles found
    ├─ LLM decides: "Need to call search_policy_documents"
    ├─ Execute tool → RAG semantic search
    ├─ Observe results → 3 relevant policy docs
    └─ LLM generates final answer
    ↓
[4] Stream response (astream_events v2)
    ├─ on_chat_model_stream → Token chunks
    ├─ on_tool_start → "🔧 Searching quotations..."
    └─ on_tool_end → "✅ Found 4 results"
    ↓
[5] Save to Supabase (chat_sessions table)
    ↓
Response to User
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

## Logging & Monitoring

Zeus AI Service provides **comprehensive task-by-task logging** to track every operation in real-time. All logs are formatted with timestamps, log levels, and emoji indicators for easy visual scanning.

### Log Categories

| Category | Logger Name | Description |
|---|---|---|
| **Main API** | `zeus` | Request/response tracking, session management, agent execution |
| **Quotation Search** | `zeus.tools.quotation` | Vehicle search attempts, fallback strategies, result counts |
| **Policy RAG** | `zeus.tools.policy_rag` | Embedding generation, semantic search, document retrieval |
| **Create Quotation** | `zeus.tools.create_quotation` | Quotation creation, validation, database insertion |
| **Order Management** | `zeus.tools.order` | Order creation, payment updates, status checks |

### Example Log Output

```
2026-03-02 12:30:45 [INFO] zeus: ================================================================================
2026-03-02 12:30:45 [INFO] zeus: 📨 [CHAT REQUEST] New chat request received
2026-03-02 12:30:45 [INFO] zeus:    Session ID: abc-123-def
2026-03-02 12:30:45 [INFO] zeus:    Model: gemini-2.5-flash
2026-03-02 12:30:45 [INFO] zeus:    Message: ประกันชั้น 1 Honda Civic e:HEV RS 2024 เท่าไร?
2026-03-02 12:30:45 [INFO] zeus:    Has Image: False
2026-03-02 12:30:45 [INFO] zeus: 📚 [HISTORY] Fetching chat history...
2026-03-02 12:30:45 [INFO] zeus:    Retrieved 0 previous messages
2026-03-02 12:30:45 [INFO] zeus: 🤖 [AGENT] Creating agent executor with model: gemini-2.5-flash
2026-03-02 12:30:45 [INFO] zeus: 🔄 [AGENT] Invoking agent executor...
2026-03-02 12:30:46 [INFO] zeus.tools.quotation: 🔍 [QUOTATION SEARCH] Starting vehicle search
2026-03-02 12:30:46 [INFO] zeus.tools.quotation:    Brand: Honda
2026-03-02 12:30:46 [INFO] zeus.tools.quotation:    Model: Civic
2026-03-02 12:30:46 [INFO] zeus.tools.quotation:    Sub-model: e:HEV RS
2026-03-02 12:30:46 [INFO] zeus.tools.quotation:    Year: 2024
2026-03-02 12:30:46 [INFO] zeus.tools.quotation: 🎯 [ATTEMPT 1] Exact match search (all parameters)
2026-03-02 12:30:46 [INFO] zeus.tools.quotation: ✅ [SUCCESS] Found 4 exact matches
2026-03-02 12:30:47 [INFO] zeus: ✅ [AGENT] Agent execution completed
2026-03-02 12:30:47 [INFO] zeus: 💾 [STORAGE] Saving messages to database...
2026-03-02 12:30:47 [INFO] zeus: ✅ [STORAGE] Messages saved successfully
2026-03-02 12:30:47 [INFO] zeus: 📤 [RESPONSE] Sending reply (523 chars)
2026-03-02 12:30:47 [INFO] zeus: ================================================================================
```

### Streaming Logs (SSE)

```
2026-03-02 12:35:10 [INFO] zeus: 🌊 [STREAM] Starting streaming response
2026-03-02 12:35:10 [INFO] zeus: 🔧 [TOOL START] search_policy_documents
2026-03-02 12:35:10 [INFO] zeus.tools.policy_rag: 📚 [POLICY RAG] Starting semantic search
2026-03-02 12:35:10 [INFO] zeus.tools.policy_rag:    Query: Does Type 1 cover flood damage?
2026-03-02 12:35:10 [INFO] zeus.tools.policy_rag:    Section filter: Coverage
2026-03-02 12:35:10 [INFO] zeus.tools.policy_rag: 🔢 [EMBEDDING] Generating query embedding...
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag:    Original dimensions: 768
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag:    Trimmed to: 2000 dimensions
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag: 🔍 [DATABASE] Calling match_documents RPC...
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag: 📊 [RESULTS] Received 3 matches
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag:    [1] Similarity: 0.8234 | Flood and Fire Coverage: Protects the insured vehicle...
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag:    [2] Similarity: 0.7891 | Flooding Scenario — Driving into Flooded Road...
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag:    [3] Similarity: 0.7456 | Deductible Definition: A deductible (or excess)...
2026-03-02 12:35:11 [INFO] zeus.tools.policy_rag: ✅ [SUCCESS] Returning 3 relevant document(s)
2026-03-02 12:35:11 [INFO] zeus: ✅ [TOOL END] search_policy_documents
2026-03-02 12:35:13 [INFO] zeus: 🏁 [STREAM] Stream completed successfully
```

### Order Creation Logs

```
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: 📝 [CREATE QUOTATION] Starting quotation creation
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Session ID: abc-123-def
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Car Model ID: 5
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Plan ID: 1
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Customer: John Doe
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: 🔍 [DATABASE] Fetching quotation details from view...
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: ✅ [FOUND] Honda Civic e:HEV RS (2024)
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Plan: Zeus Comprehensive Plus (Type 1)
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Premium: 25000.00 THB
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation:    Deductible: 0.00 THB
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: 🔢 [GENERATE] Quotation number: QT-20260302-A1B2
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: 📅 [VALIDITY] Valid until: 2026-04-01
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: 💰 [CALCULATE] Total premium: 25000.0 THB
2026-03-02 13:00:00 [INFO] zeus.tools.create_quotation: 💾 [DATABASE] Inserting quotation record: QT-20260302-A1B2
2026-03-02 13:00:01 [INFO] zeus.tools.create_quotation: ✅ [SUCCESS] Quotation created successfully
2026-03-02 13:00:01 [INFO] zeus.tools.create_quotation:    Quotation ID: uuid-here
2026-03-02 13:00:01 [INFO] zeus.tools.create_quotation:    Quotation Number: QT-20260302-A1B2
2026-03-02 13:00:01 [INFO] zeus.tools.create_quotation:    Status: draft
```

### Viewing Logs

**Console output** (default):
```bash
python -m uvicorn main:app --reload --port 8000
```

**Save to file**:
```bash
python -m uvicorn main:app --reload --port 8000 2>&1 | tee zeus-ai.log
```

**Filter by component**:
```bash
# Only quotation search logs
python -m uvicorn main:app --reload --port 8000 2>&1 | grep "zeus.tools.quotation"

# Only RAG logs
python -m uvicorn main:app --reload --port 8000 2>&1 | grep "zeus.tools.policy_rag"
```

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
