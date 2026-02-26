# Zeus — AI Fintech Insurance App

A full-stack mobile fintech insurance quotation app powered by Google Gemini AI, LangGraph, Supabase pgvector, ASP.NET Core BFF, and .NET MAUI.

---

## Architecture

```
[.NET MAUI App]  ──►  [ASP.NET Core BFF]  ──►  [Python FastAPI AI Service]
                                                         │
                                              ┌──────────┴──────────┐
                                        [Supabase pgvector]   [Gemini AI]
                                         car_brands            gemini-2.5-flash
                                         car_models            gemini-embedding-001
                                         insurance_plans       
                                         plan_coverages
                                         plan_premiums
                                         vw_quotation_details
                                         policy_documents (VECTOR 2000)
                                         chat_sessions
```

---

## Project Structure

```
zeus-agentic-rag-ai/
├── zeus-ai-service/          # Python FastAPI + LangGraph + Gemini
│   ├── init_supabase.sql     # ← Run this first in Supabase SQL Editor
│   ├── ingest_embeddings.py  # ← Run this to generate pgvector embeddings
│   ├── main.py               # FastAPI server endpoint
│   ├── database.py           # Supabase client helper
│   ├── agent.py              # LangGraph ReAct Agent definition
│   ├── requirements.txt
│   ├── .env.example
│   └── tools/
│       ├── quotation_db_tool.py  # Queries vw_quotation_details view
│       └── policy_rag_tool.py    # Semantic search over policy_documents
├── Zeus.BFF/                 # C# ASP.NET Core Clean Architecture
│   ├── Zeus.Domain/
│   ├── Zeus.Application/
│   ├── Zeus.Infrastructure/
│   └── Zeus.WebApi/
└── Zeus.MAUI/                # .NET MAUI Mobile App (MVVM)
    ├── Models/
    ├── Services/
    ├── ViewModels/
    ├── Views/
    └── Converters/
```

---

## Setup Guide

### STEP 0 — Initialize Supabase Database

1. Go to [Supabase Dashboard](https://supabase.com/dashboard) → your project → **SQL Editor**
2. Paste the contents of `zeus-ai-service/init_supabase.sql` and click **Run**
3. This creates all relational tables (`car_brands`, `car_models`, `insurance_plans`, etc.), the `policy_documents` RAG table, `chat_sessions`, the `vw_quotation_details` view, RLS policies, and extensive mock data.

> **Note:** The `policy_documents.embedding` column is initialized as `NULL`.  
> You must run the Python ingestion script (`ingest_embeddings.py`) to generate `VECTOR(2000)` embeddings using Google's embedding model before the RAG tool will work.

---

### STEP 1 — Python FastAPI AI Service

**Prerequisites:** Python 3.11+

```bash
cd zeus-ai-service

# Create and activate virtual environment
python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate     # macOS/Linux

# Install dependencies
pip install -r requirements.txt

# Configure environment
copy .env.example .env
# Edit .env and fill in:
# GEMINI_API_KEY from Google AI Studio
# SUPABASE_URL from Supabase Project Settings
# SUPABASE_SERVICE_KEY from Supabase API Settings (service_role)
```

**`.env` file:**
```env
GEMINI_API_KEY=AIzaSy...
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_SERVICE_KEY=<your-service-role-key>
```

**Generate Embeddings (Required once):**
```bash
python ingest_embeddings.py
```

**Run the service:**
```bash
python -m uvicorn main:app --reload --port 8000
```

**Test endpoint:**
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"session_id":"test-001","message":"What is the insurance premium for a Honda Civic Type R 2024?"}'
```

---

### STEP 2 — C# ASP.NET Core BFF

**Prerequisites:** .NET 8 SDK

```bash
cd Zeus.BFF

# Restore and run
dotnet restore Zeus.WebApi/Zeus.WebApi.csproj
dotnet run --project Zeus.WebApi/Zeus.WebApi.csproj
```

The BFF runs on `http://localhost:5000` by default and proxies to the Python AI service at `http://localhost:8000`.

Swagger UI available at: `http://localhost:5000/swagger`

---

### STEP 3 — .NET MAUI App

**Prerequisites:** .NET 8 + MAUI workload installed

```bash
cd Zeus.MAUI

# Restore packages
dotnet restore

# Run on Android emulator
dotnet build -t:Run -f net8.0-android

# Run on Windows
dotnet build -t:Run -f net8.0-windows10.0.19041.0
```

> **BFF URL:** Update `bffBaseUrl` in `MauiProgram.cs` to match your BFF host (e.g., use your machine's local IP for Android emulator: `http://10.0.2.2:5000`).

---

## Data Flow

```
User types message / uploads photo
         │
         ▼
[MAUI ChatViewModel]
  - session_id (Guid, persisted per app session)
  - image → base64
         │
         ▼ POST /api/chat
[ASP.NET BFF ChatController]
  - Forwards to Python AI service
         │
         ▼ POST /api/chat
[FastAPI main.py]
  1. Fetch chat history from Supabase (chat_sessions)
  2. Build LangChain message history
  3. Invoke LangGraph ReAct Agent (Gemini 2.5 Flash)
         │
    ┌────┴──────┐
    ▼           ▼
[quotation_db] [policy_rag]
 supabase-py   pgvector RPC
 SELECT only   semantic search
    └────┬──────┘
         ▼
  4. Save user + AI messages to chat_sessions
  5. Return reply
```

---

## Security Notes

- **Read-Only DB Access:** The agent tools (`quotation_db_tool`, `policy_rag_tool`) use `supabase-py` client with `.select()` and `.rpc()` calls only. RLS on the tables blocks INSERT/UPDATE/DELETE from the client interface level, ensuring the AI cannot modify records.
- **API Key:** Never commit `.env`. Use `.env.example` as the template.
- **SUPABASE_SERVICE_KEY:** Use the service role key only in the backend (Python service). Never expose it in the MAUI app.
