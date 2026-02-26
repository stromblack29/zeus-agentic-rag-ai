"""
One-time script to generate and store embeddings for all policy_documents rows
that currently have a NULL embedding.

Usage:
    python ingest_embeddings.py

Requires .env to be configured with GEMINI_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY.
"""

import os
import time
from dotenv import load_dotenv

load_dotenv()

from database import get_supabase_client
from langchain_google_genai import GoogleGenerativeAIEmbeddings


BATCH_SIZE = 5
SLEEP_BETWEEN_BATCHES = 1.0


def fetch_documents_without_embeddings(client) -> list[dict]:
    response = (
        client.table("policy_documents")
        .select("id, content")
        .is_("embedding", "null")
        .order("id", desc=False)
        .execute()
    )
    return response.data or []


def update_embedding(client, doc_id: int, embedding: list[float]) -> None:
    client.table("policy_documents").update(
        {"embedding": embedding}
    ).eq("id", doc_id).execute()


def main() -> None:
    client = get_supabase_client()

    embeddings_model = GoogleGenerativeAIEmbeddings(
        model="models/gemini-embedding-001",
        google_api_key=os.environ["GEMINI_API_KEY"],
    )

    docs = fetch_documents_without_embeddings(client)

    if not docs:
        print("✅ All policy_documents already have embeddings. Nothing to do.")
        return

    print(f"📄 Found {len(docs)} document(s) without embeddings. Starting ingestion...\n")

    for i in range(0, len(docs), BATCH_SIZE):
        batch = docs[i : i + BATCH_SIZE]
        texts = [doc["content"] for doc in batch]

        print(f"  Embedding batch {i // BATCH_SIZE + 1} ({len(batch)} docs)...")

        embeddings = embeddings_model.embed_documents(texts)

        for doc, embedding in zip(batch, embeddings):
            # Trim the embedding to 2000 dimensions to match the Supabase VECTOR(2000) column
            trimmed_embedding = embedding[:2000]
            update_embedding(client, doc["id"], trimmed_embedding)
            print(f"    ✔ Updated doc id={doc['id']} — {doc['content'][:60]}...")

        if i + BATCH_SIZE < len(docs):
            time.sleep(SLEEP_BETWEEN_BATCHES)

    print(f"\n✅ Ingestion complete. {len(docs)} document(s) embedded and saved.")


if __name__ == "__main__":
    main()
