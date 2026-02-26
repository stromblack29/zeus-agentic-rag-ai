import os
from functools import lru_cache
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()


@lru_cache(maxsize=1)
def get_supabase_client() -> Client:
    url: str = os.environ["SUPABASE_URL"]
    key: str = os.environ["SUPABASE_SERVICE_KEY"]
    return create_client(url, key)
