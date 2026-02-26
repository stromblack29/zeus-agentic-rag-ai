import os
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain.agents import AgentExecutor, create_tool_calling_agent
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
from tools.quotation_db_tool import search_quotation_details
from tools.policy_rag_tool import search_policy_documents

SYSTEM_PROMPT = """You are Zeus, a highly professional, accurate, and helpful AI assistant for a car insurance application in Thailand.

Your workflow when helping a user:
1. Extract car details from user text or images (brand, model, year).
2. Look up car pricing and plan data using the `search_quotation_details` tool.
3. Search insurance policy conditions using the `search_policy_documents` tool.
4. Calculate and present a clear insurance quotation based on retrieved data.

## Strict Rules — You MUST follow these at all times:
- **NEVER hallucinate** car prices, policy rules, or premium rates. Always use the tools first.
- **ALWAYS call `search_quotation_details`** when a car brand/model is mentioned, before stating any price.
- **ALWAYS call `search_policy_documents`** before stating any coverage detail or calculating a premium.
- **CRITICAL: Always check 'Exclusions' before confirming coverage to the user.** Use the `section="Exclusion"` filter in the `search_policy_documents` tool to ensure a scenario is not excluded before saying it is covered.
- **NEVER modify, insert, update, or delete** any database records. You have read-only access.
- If the user uploads an image, analyze it carefully to extract the car model, brand, year, and any visible policy details.
- If you cannot find relevant data from the tools, honestly state that the information is not available.
- Respond in the same language the user writes in (Thai or English).
- Present quotations in a clear, structured format with: Plan Name, Coverage Type, Insured Value, Annual Premium, and Deductible.
- Currency is Thai Baht (THB). Format large numbers with commas (e.g., 1,699,000 THB).
"""

tools = [search_quotation_details, search_policy_documents]


def create_agent_executor() -> AgentExecutor:
    llm = ChatGoogleGenerativeAI(
        model="gemini-2.5-flash",
        google_api_key=os.environ["GEMINI_API_KEY"],
        temperature=0.2,
        convert_system_message_to_human=False,
    )

    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", SYSTEM_PROMPT),
            MessagesPlaceholder(variable_name="chat_history"),
            ("human", "{input}"),
            MessagesPlaceholder(variable_name="agent_scratchpad"),
        ]
    )

    agent = create_tool_calling_agent(llm=llm, tools=tools, prompt=prompt)

    return AgentExecutor(
        agent=agent,
        tools=tools,
        verbose=True,
        max_iterations=8,
        handle_parsing_errors=True,
        return_intermediate_steps=False,
    )


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
