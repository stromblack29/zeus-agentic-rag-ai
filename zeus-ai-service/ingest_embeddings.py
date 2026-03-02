"""
Script to generate and store embeddings for policy_documents rows
that currently have a NULL embedding.

Usage:
    # Embed all documents without embeddings (default)
    python ingest_embeddings.py

    # Re-embed all documents (force re-ingestion)
    python ingest_embeddings.py --force

    # Embed only a specific plan type
    python ingest_embeddings.py --plan-type "Type 1"

    # Embed only a specific section
    python ingest_embeddings.py --section "Coverage"

Requires .env to be configured with GEMINI_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_KEY.
"""

import os
import sys
import time
import argparse
from dotenv import load_dotenv

load_dotenv()

from database import get_supabase_client
from langchain_google_genai import GoogleGenerativeAIEmbeddings


BATCH_SIZE = 5
SLEEP_BETWEEN_BATCHES = 1.2
MAX_RETRIES = 3
VECTOR_DIMENSIONS = 2000


def fetch_documents(client, force: bool = False, plan_type: str = None, section: str = None) -> list[dict]:
    query = client.table("policy_documents").select("id, plan_type, section, content")

    if not force:
        query = query.is_("embedding", "null")

    if plan_type:
        query = query.eq("plan_type", plan_type)

    if section:
        query = query.eq("section", section)

    response = query.order("created_at", desc=False).execute()
    return response.data or []


def update_embedding(client, doc_id: str, embedding: list[float]) -> None:
    client.table("policy_documents").update(
        {"embedding": embedding}
    ).eq("id", doc_id).execute()


def embed_with_retry(embeddings_model, texts: list[str], retries: int = MAX_RETRIES) -> list[list[float]]:
    for attempt in range(1, retries + 1):
        try:
            return embeddings_model.embed_documents(texts)
        except Exception as e:
            if attempt == retries:
                raise
            wait = attempt * 2.0
            print(f"    ⚠ Attempt {attempt} failed: {e}. Retrying in {wait}s...")
            time.sleep(wait)


def print_summary(total: int, succeeded: int, failed: list[str]) -> None:
    print(f"\n{'='*60}")
    print(f"📊 Ingestion Summary")
    print(f"{'='*60}")
    print(f"  Total documents processed : {total}")
    print(f"  ✅ Successfully embedded  : {succeeded}")
    print(f"  ❌ Failed                 : {len(failed)}")
    if failed:
        print(f"\n  Failed document IDs:")
        for fid in failed:
            print(f"    - {fid}")
    print(f"{'='*60}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest embeddings for Zeus policy documents")
    parser.add_argument("--force", action="store_true", help="Re-embed all documents, even those with existing embeddings")
    parser.add_argument("--plan-type", type=str, default=None, help="Filter by plan_type (e.g. 'Type 1', 'All')")
    parser.add_argument("--section", type=str, default=None, help="Filter by section (e.g. 'Coverage', 'Exclusion', 'Condition')")
    args = parser.parse_args()

    client = get_supabase_client()

    embeddings_model = GoogleGenerativeAIEmbeddings(
        model="models/gemini-embedding-001",
        google_api_key=os.environ["GEMINI_API_KEY"],
    )

    docs = fetch_documents(client, force=args.force, plan_type=args.plan_type, section=args.section)

    if not docs:
        print("✅ No documents to embed. All policy_documents already have embeddings.")
        if args.force:
            print("   (--force flag was set but no matching documents found)")
        return

    mode = "force re-embed" if args.force else "new only"
    filters = []
    if args.plan_type:
        filters.append(f"plan_type={args.plan_type}")
    if args.section:
        filters.append(f"section={args.section}")
    filter_str = f" [{', '.join(filters)}]" if filters else ""

    print(f"📄 Found {len(docs)} document(s) to embed ({mode}){filter_str}")
    print(f"   Model  : models/gemini-embedding-001")
    print(f"   Dims   : {VECTOR_DIMENSIONS}")
    print(f"   Batch  : {BATCH_SIZE}")
    print()

    succeeded = 0
    failed_ids = []
    total_batches = (len(docs) + BATCH_SIZE - 1) // BATCH_SIZE

    for i in range(0, len(docs), BATCH_SIZE):
        batch = docs[i : i + BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1
        texts = [doc["content"] for doc in batch]

        print(f"  Batch {batch_num}/{total_batches} — {len(batch)} doc(s)...")

        try:
            embeddings = embed_with_retry(embeddings_model, texts)

            for doc, embedding in zip(batch, embeddings):
                trimmed = embedding[:VECTOR_DIMENSIONS]
                update_embedding(client, doc["id"], trimmed)
                section_label = doc.get("section", "?")
                plan_label = doc.get("plan_type", "?")
                print(f"    ✔ [{plan_label}/{section_label}] {doc['content'][:70]}...")
                succeeded += 1

        except Exception as e:
            print(f"    ❌ Batch {batch_num} failed permanently: {e}")
            for doc in batch:
                failed_ids.append(doc["id"])

        if i + BATCH_SIZE < len(docs):
            time.sleep(SLEEP_BETWEEN_BATCHES)

    print_summary(len(docs), succeeded, failed_ids)

    if failed_ids:
        sys.exit(1)


if __name__ == "__main__":
    main()
