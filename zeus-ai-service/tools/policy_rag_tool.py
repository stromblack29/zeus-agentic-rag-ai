import json
import os
from langchain_core.tools import tool
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from database import get_supabase_client


def _get_embeddings_model() -> GoogleGenerativeAIEmbeddings:
    return GoogleGenerativeAIEmbeddings(
        model="models/gemini-embedding-001",
        google_api_key=os.environ["GEMINI_API_KEY"],
    )


@tool
def search_policy_documents(query: str, section: str = None) -> str:
    """
    Search the insurance policy documents knowledge base using semantic similarity.
    Use this tool to find relevant policy conditions, coverage rules, premium
    calculation methods, deductibles, claim procedures, and eligibility criteria.

    Args:
        query: A detailed natural language question about the insurance policy.
               (e.g., "Does this cover flood damage?" or "What is the deductible?")
        section: Optional. Filter by document section. Valid values are:
                 'Coverage', 'Exclusion', 'Condition', 'Definition'.
                 Highly recommended to use 'Exclusion' when checking if something is NOT covered.

    Returns:
        A JSON string with the most relevant policy document excerpts and their
        similarity scores.
    """
    print(f"\n[RAG TOOL START] Received query: '{query}' | Section filter: {section}")
    client = get_supabase_client()
    
    print(f"[RAG TOOL] Getting embeddings for query...")
    embeddings_model = _get_embeddings_model()
    query_embedding = embeddings_model.embed_query(query)

    # Trim to 2000 dimensions to match DB schema
    trimmed_query_embedding = query_embedding[:2000]
    print(f"[RAG TOOL] Query embedded. Sending RPC call to Supabase...")

    response = client.rpc(
        "match_documents",
        {
            "query_embedding": trimmed_query_embedding,
            "match_threshold": 0.4,
            "match_count": 4,
            "filter_section": section
        },
    ).execute()

    print(f"[RAG TOOL] RPC response received. Number of raw matches: {len(response.data) if response.data else 0}")

    if not response.data:
        print("[RAG TOOL] No documents found above threshold.")
        return json.dumps(
            {
                "result": "No relevant policy documents found for this query.",
                "documents": [],
            }
        )

    documents = [
        {
            "content": doc["content"],
            "metadata": doc["metadata"],
            "similarity": round(doc["similarity"], 4),
        }
        for doc in response.data
    ]
    
    print(f"[RAG TOOL END] Processed {len(documents)} document(s) for LLM analysis.")

    return json.dumps(
        {
            "result": f"Found {len(documents)} relevant policy document(s).",
            "documents": documents,
        }
    )

