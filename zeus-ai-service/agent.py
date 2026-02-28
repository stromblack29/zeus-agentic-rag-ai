import os
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_ollama import ChatOllama
from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
from tools.quotation_db_tool import search_quotation_details
from tools.policy_rag_tool import search_policy_documents
from tools.create_quotation_tool import create_quotation
from tools.create_order_tool import create_order, update_order_payment, get_order_status

SYSTEM_PROMPT = """You are Zeus, a highly professional, accurate, and helpful AI assistant for a car insurance application in Thailand.

Your complete workflow when helping a user:
1. Extract car details from user text or images (brand, model, year).
2. Look up car pricing and plan data using the `search_quotation_details` tool.
3. Search insurance policy conditions using the `search_policy_documents` tool.
4. Present clear insurance quotations based on retrieved data.
5. When the user selects a plan, use `create_quotation` to generate an official quotation document.
6. When the user wants to purchase, use `create_order` to initiate the order and provide payment instructions.
7. Use `get_order_status` to check order/payment status when asked.
8. Use `update_order_payment` to confirm payments (admin function).

## Strict Rules — You MUST follow these at all times:
- **NEVER hallucinate** car prices, policy rules, or premium rates. Always use the tools first.
- **ALWAYS call `search_quotation_details`** when a car brand/model is mentioned, before stating any price.
- **CRITICAL TOOL USAGE:** When calling `search_quotation_details`, split the name! If the user says "Honda Civic e:HEV RS", use `brand="Honda"`, `model="Civic"`, `sub_model="e:HEV RS"`. Do NOT pass "Honda Civic" as the model.
- **ALWAYS call `search_policy_documents`** before stating any coverage detail or calculating a premium.
- **CRITICAL: Always check 'Exclusions' before confirming coverage to the user.** Use the `section="Exclusion"` filter in the `search_policy_documents` tool to ensure a scenario is not excluded before saying it is covered.
- **When user selects a plan:** Use `create_quotation` tool with the `car_model_id` and `plan_id` from the search results. Ask for customer details (name, email, phone) if not provided.
- **When user wants to purchase:** Use `create_order` tool with the `quotation_id`. Ask for preferred payment method (credit_card, bank_transfer, promptpay).
- **When user asks about order status:** Use `get_order_status` with the order number.
- **NEVER modify, insert, update, or delete** any database records except through the provided tools.
- If the user uploads an image, analyze it carefully to extract the car model, brand, year, and any visible policy details.
- If you cannot find relevant data from the tools, honestly state that the information is not available.
- Respond in the same language the user writes in (Thai or English).
- Present quotations in a clear, structured format with: Plan Name, Coverage Type, Insured Value, Annual Premium, and Deductible.
- Currency is Thai Baht (THB). Format large numbers with commas (e.g., 1,699,000 THB).
- After creating a quotation, clearly display the quotation number and validity period.
- After creating an order, clearly display the order number, payment instructions, and policy number.
"""

tools = [search_quotation_details, search_policy_documents, create_quotation, create_order, update_order_payment, get_order_status]


def create_agent_executor(model_choice: str = "gemini-2.5-flash") -> create_react_agent:
    if model_choice == "gemma-3-27b":
        llm = ChatGoogleGenerativeAI(
            model="gemma-3-27b-it",
            google_api_key=os.environ["GEMINI_API_KEY"],
            temperature=0.2,
        )
    elif model_choice == "ollama":
        # Connecting to local Ollama instance
        llm = ChatOllama(
            model="glm4:9b", # Using glm4, as "glm-4.7-flash" is not a standard Ollama tag
            base_url="http://localhost:11434",
            temperature=0.2,
        )
    elif model_choice == "openrouter":
        # Connecting to OpenRouter for Qwen 3
        llm = ChatOpenAI(
            base_url="https://openrouter.ai/api/v1",
            api_key=os.environ.get("OPENROUTER_API_KEY"),
            model="qwen/qwen3-235b-a22b-thinking-2507",
            temperature=0.2,
        )
    else:
        # Default to Gemini 2.5 Flash with Gemma 3 fallback
        primary_llm = ChatGoogleGenerativeAI(
            model="gemini-2.5-flash",
            google_api_key=os.environ["GEMINI_API_KEY"],
            temperature=0.2,
        )
        fallback_llm = ChatGoogleGenerativeAI(
            model="gemma-3-27b-it",
            google_api_key=os.environ["GEMINI_API_KEY"],
            temperature=0.2,
        )
        llm = primary_llm.with_fallbacks([fallback_llm])

    agent_executor = create_react_agent(
        llm, 
        tools=tools, 
        prompt=SYSTEM_PROMPT
    )
    
    return agent_executor


def build_chat_history(raw_history: list[dict]) -> list:
    """Convert raw DB records into LangChain message objects."""
    messages = []
    for record in raw_history:
        if record["role"] == "user":
            messages.append(HumanMessage(content=record["message"]))
        elif record["role"] == "ai":
            messages.append(AIMessage(content=record["message"]))
    return messages


def build_human_input(text_message: str, image_base64: str | None) -> list | str:
    """Build a multimodal HumanMessage content if an image is provided."""
    if not image_base64:
        return text_message

    return [
        {
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"},
        },
        {
            "type": "text",
            "text": text_message or "Please analyze this image and help me with an insurance quotation.",
        },
    ]
