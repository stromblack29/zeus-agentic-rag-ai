# Zeus Insurance AI - Deployment Guide

## Overview
This guide covers deploying the expanded Zeus Insurance AI system with comprehensive Thai market data, quotation management, and multi-LLM support.

## What's New in V2

### 1. Expanded Database (60+ Vehicles)
- **20 Car Brands**: Honda, Toyota, Mazda, Isuzu, Mitsubishi, Nissan, Ford, Chevrolet, MG, BYD, GWM, Tesla, BMW, Mercedes-Benz, Audi, Porsche, Volvo, Subaru, Suzuki, Hyundai
- **60+ Vehicle Models**: Covering economy cars to luxury vehicles and EVs
- **Realistic Thai Market Pricing**: Based on 2024 market values

### 2. Quotation & Order Management
- **Quotations Table**: Stores generated quotes with customer details, validity period, and status tracking
- **Orders Table**: Tracks purchases, payments, and policy activation
- **Quotation Tool**: AI can now create official quotations after customer selects a plan

### 3. Enhanced Policy Documents (40+ Entries)
- Comprehensive coverage details for all plan types
- Detailed exclusions and conditions
- Claims process documentation
- Add-on coverage options
- Payment and billing terms
- Special conditions for young drivers, high-performance vehicles, etc.

### 4. Multi-LLM Support
- **Gemini 2.5 Flash** (default with Gemma 3 27B fallback)
- **Gemma 3 27B** (Google AI Studio)
- **Ollama** (local - glm4:9b)
- **OpenRouter** (Qwen 3 235B)

## Deployment Steps

### Step 1: Update Database Schema

1. **Open Supabase SQL Editor**
   - Go to your Supabase project dashboard
   - Navigate to SQL Editor

2. **Run the New Schema**
   ```sql
   -- Copy and paste the entire contents of init_supabase_v2.sql
   -- This will drop old tables and create new ones with expanded data
   ```

3. **Verify Tables Created**
   Check that these tables exist:
   - `car_brands` (20 brands)
   - `car_models` (60+ models)
   - `insurance_plans` (4 plans)
   - `plan_coverages` (coverage details)
   - `plan_premiums` (premium matrix)
   - `policy_documents` (40+ documents)
   - `quotations` (NEW - for storing quotes)
   - `orders` (NEW - for tracking purchases)
   - `chat_sessions` (conversation history)

### Step 2: Re-ingest Embeddings

The new policy documents need to be embedded for RAG search:

```bash
cd zeus-ai-service
python ingest_embeddings.py
```

This will:
- Fetch all policy documents without embeddings
- Generate embeddings using Google's `gemini-embedding-001` model
- Update the database with 2000-dimension vectors
- Enable semantic search on the new content

**Expected Output:**
```
Processing 40+ documents...
Embedding document 1/40...
Embedding document 2/40...
...
All embeddings updated successfully!
```

### Step 3: Verify Environment Variables

Ensure your `.env` file contains:

```env
GEMINI_API_KEY=your_google_api_key_here
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_service_key_here
OPENROUTER_API_KEY=your_openrouter_key_here  # Optional
```

### Step 4: Test the System

Start the FastAPI server:

```bash
cd zeus-ai-service
python -m uvicorn main:app --reload --port 8000
```

#### Test 1: Basic Quotation Search
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "I want insurance for Honda Civic e:HEV RS 2024",
    "llm_model": "gemini-2.5-flash"
  }'
```

**Expected Response:**
- AI should call `search_quotation_details` with split parameters
- Return multiple plan options (Type 1, Type 2+, Type 3+)
- Display premiums and deductibles

#### Test 2: Policy Questions
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Does Type 1 cover flood damage?",
    "llm_model": "gemini-2.5-flash"
  }'
```

**Expected Response:**
- AI should call `search_policy_documents` with query
- Return relevant policy excerpts about flood coverage
- Cite specific coverage details

#### Test 3: Create Quotation
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test-session-123",
    "message": "I want to proceed with Zeus Comprehensive Plus for the Civic",
    "llm_model": "gemini-2.5-flash"
  }'
```

**Expected Response:**
- AI should ask for customer details (name, email, phone)
- After receiving details, call `create_quotation` tool
- Return quotation number (format: QT-YYYYMMDD-XXXX)
- Display validity period (30 days from creation)

#### Test 3b: Create Order from Quotation
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "test-session-123",
    "message": "I want to buy this insurance, please proceed with payment",
    "llm_model": "gemini-2.5-flash"
  }'
```

**Expected Response:**
- AI should call `create_order` with the quotation_id
- Ask for payment method preference
- Return order number (format: ORD-YYYYMMDD-XXXX)
- Display payment instructions based on selected method
- Show policy number and coverage dates
- Policy status will be "inactive" until payment confirmed

#### Test 3c: Check Order Status
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is the status of order ORD-20240228-A1B2?",
    "llm_model": "gemini-2.5-flash"
  }'
```

**Expected Response:**
- AI should call `get_order_status` with order number
- Return payment status, policy status, and order details

#### Test 4: Alternative LLM Models
```bash
# Test with Gemma 3 27B
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Show me insurance for Toyota Camry",
    "llm_model": "gemma-3-27b"
  }'

# Test with OpenRouter (Qwen 3)
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What are the exclusions for Type 2+ insurance?",
    "llm_model": "openrouter"
  }'
```

### Step 5: Monitor Logs

Watch the console for debug logs:

```
[TOOL] search_quotation_details → brand='Honda', model='Civic', sub_model='e:HEV RS', year=2024

[RAG TOOL START] Received query: 'flood coverage' | Section filter: Coverage
[RAG TOOL] Getting embeddings for query...
[RAG TOOL] Query embedded. Sending RPC call to Supabase...
[RAG TOOL] RPC response received. Number of raw matches: 3
[RAG TOOL END] Processed 3 document(s) for LLM analysis.

[CREATE QUOTATION] Starting quotation creation for session test-session-123
[CREATE QUOTATION] Car Model ID: 2, Plan ID: 1
[CREATE QUOTATION] Found details: Honda Civic e:HEV RS - Zeus Comprehensive Plus
[CREATE QUOTATION] SUCCESS: Quotation created with ID abc-123-def
```

## Database Schema Reference

### Quotations Table
```sql
CREATE TABLE quotations (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL,
    car_model_id INT REFERENCES car_models(id),
    plan_id INT REFERENCES insurance_plans(id),
    customer_name VARCHAR(200),
    customer_email VARCHAR(200),
    customer_phone VARCHAR(50),
    car_estimated_price NUMERIC(12, 2),
    base_premium NUMERIC(12, 2),
    deductible NUMERIC(12, 2),
    total_premium NUMERIC(12, 2),
    quotation_number VARCHAR(50) UNIQUE,
    valid_until TIMESTAMPTZ,
    status VARCHAR(50), -- draft, sent, accepted, expired
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Orders Table
```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    quotation_id UUID REFERENCES quotations(id),
    order_number VARCHAR(50) UNIQUE,
    payment_status VARCHAR(50), -- pending, paid, failed, refunded
    payment_method VARCHAR(50),
    payment_date TIMESTAMPTZ,
    policy_number VARCHAR(50) UNIQUE,
    policy_start_date DATE,
    policy_end_date DATE,
    policy_status VARCHAR(50), -- inactive, active, cancelled, expired
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

## API Endpoints

### POST /api/chat
Main chat endpoint with LLM selection.

**Request:**
```json
{
  "session_id": "uuid-string",
  "message": "user message",
  "image_base64": "optional-base64-image",
  "llm_model": "gemini-2.5-flash" // or "gemma-3-27b", "ollama", "openrouter"
}
```

**Response:**
```json
{
  "session_id": "uuid-string",
  "reply": "AI response",
  "model_used": "gemini-2.5-flash"
}
```

### GET /health
Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "service": "zeus-ai-service"
}
```

## Tools Available to AI

### 1. search_quotation_details
Searches car models and insurance plans.

**Parameters:**
- `brand` (optional): Car brand (e.g., "Honda")
- `model` (optional): Car model (e.g., "Civic")
- `sub_model` (optional): Trim level (e.g., "e:HEV RS")
- `year` (optional): Year (e.g., 2024)

### 2. search_policy_documents
Semantic search on policy documents.

**Parameters:**
- `query` (required): Natural language question
- `section` (optional): Filter by "Coverage", "Exclusion", "Condition", "Definition"

### 3. create_quotation
Creates official quotation after plan selection.

**Parameters:**
- `session_id` (required): Current session UUID
- `car_model_id` (required): ID from search results
- `plan_id` (required): ID from search results
- `customer_name` (optional): Customer name
- `customer_email` (optional): Customer email
- `customer_phone` (optional): Customer phone

### 4. create_order
Creates an order from an accepted quotation to initiate purchase.

**Parameters:**
- `quotation_id` (required): UUID of the quotation
- `payment_method` (optional): "credit_card", "bank_transfer", "promptpay", or "pending"

**Returns:**
- Order number, payment instructions, policy number, policy dates

### 5. update_order_payment
Updates payment status and activates policy (admin function).

**Parameters:**
- `order_id` (required): UUID of the order
- `payment_status` (required): "paid", "failed", or "refunded"
- `payment_date` (optional): ISO format date

**Returns:**
- Updated order status, policy activation confirmation

### 6. get_order_status
Retrieves current status of an order.

**Parameters:**
- `order_number` (required): Order number (e.g., "ORD-20240228-A1B2")

**Returns:**
- Order details, payment status, policy status, dates

## Troubleshooting

### Issue: Embeddings not working
**Solution:** Verify the `policy_documents` table has `embedding` column of type `VECTOR(2000)` and run `ingest_embeddings.py` again.

### Issue: Quotation creation fails
**Solution:** Check that `quotations` table exists and has proper foreign key constraints to `car_models` and `insurance_plans`.

### Issue: LLM not finding cars
**Solution:** Check logs for the exact parameters being passed to `search_quotation_details`. Ensure the AI is splitting brand/model/sub_model correctly.

### Issue: OpenRouter not working
**Solution:** Verify `OPENROUTER_API_KEY` is set in `.env` and the model name `qwen/qwen3-235b-a22b-thinking-2507` is correct.

## Next Steps

1. **Add Payment Integration**: Implement payment processing for orders table
2. **Email Notifications**: Send quotation PDFs to customer email
3. **Policy Generation**: Auto-generate policy documents after payment
4. **Admin Dashboard**: Build UI to manage quotations and orders
5. **Analytics**: Track conversion rates, popular models, etc.

## Support

For issues or questions:
- Check server logs for detailed error messages
- Verify Supabase connection and RLS policies
- Test tools individually using the debug endpoints
- Review the system prompt in `agent.py` for AI behavior rules
