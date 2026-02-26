# Zeus — AI Fintech Insurance App

A full-stack mobile fintech insurance quotation app powered by Google Gemini AI, LangChain RAG, Supabase pgvector, ASP.NET Core BFF, and .NET MAUI.

---

## Architecture

```
[.NET MAUI App]  ──►  [ASP.NET Core BFF]  ──►  [Python FastAPI AI Service]
                                                         │
                                              ┌──────────┴──────────┐
                                        [Supabase pgvector]   [Gemini AI]
                                         car_models            gemini-2.5-flash
                                         policy_documents      embedding-001
                                         chat_sessions
```

---

## Project Structure

```
zeus-agentic-rag-ai/
├── zeus-ai-service/          # Python FastAPI + LangChain + Gemini
│   ├── init_supabase.sql     # ← Run this first in Supabase SQL Editor
│   ├── main.py
│   ├── database.py
│   ├── agent.py
│   ├── requirements.txt
│   ├── .env.example
│   └── tools/
│       ├── car_db_tool.py
│       └── policy_rag_tool.py
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
3. This creates: `car_models`, `policy_documents`, `chat_sessions` tables + RLS policies + mock data

> **Note:** The `policy_documents.embedding` column is `NULL` until you run the Python ingestion step.  
> For testing the RAG tool, you can manually insert pre-computed embeddings or run a one-time ingestion script using `GoogleGenerativeAIEmbeddings`.

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
# Edit .env and fill in SUPABASE_SERVICE_KEY from:
# Supabase Dashboard → Settings → API → service_role key
```

**`.env` file:**
```env
GEMINI_API_KEY=AIzaSyALE3060fKJ0laEiB_TceBYlXpHGMI0N20
SUPABASE_URL=https://hvpgulyfjzjuhkryqxvo.supabase.co
SUPABASE_SERVICE_KEY=<your-service-role-key>
```

**Run the service:**
```bash
uvicorn main:app --reload --port 8000
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
  3. Invoke AgentExecutor (Gemini 2.5 Flash)
         │
    ┌────┴────┐
    ▼         ▼
[car_db_tool] [policy_rag_tool]
 supabase-py   pgvector RPC
 SELECT only   similarity search
    └────┬────┘
         ▼
  4. Save user + AI messages to chat_sessions
  5. Return reply
```

---

## Security Notes

- **Read-Only DB Access:** `car_db_tool` uses `supabase-py` client with only `.select()` calls. RLS on `car_models` blocks INSERT/UPDATE/DELETE at the DB level.
- **API Key:** Never commit `.env`. Use `.env.example` as the template.
- **SUPABASE_SERVICE_KEY:** Use the service role key only in the backend (Python service). Never expose it in the MAUI app.
