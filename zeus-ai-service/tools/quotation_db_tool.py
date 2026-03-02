import re
import json
import logging
from typing import Optional
from langchain_core.tools import tool
from database import get_supabase_client

logger = logging.getLogger("zeus.tools.quotation")


def _clean_sub_model(sub_model: str) -> str:
    """Remove trailing year (4-digit number) accidentally included in sub_model by the LLM."""
    return re.sub(r'\b(19|20)\d{2}\b', '', sub_model).strip().strip('-').strip()


@tool
def search_quotation_details(
    brand: Optional[str] = None,
    model: Optional[str] = None,
    sub_model: Optional[str] = None,
    year: Optional[int] = None,
) -> str:
    """
    Search the vw_quotation_details view for vehicle information and insurance premiums.
    Returns brand, model, sub_model, year, car_estimated_price, plan_type, plan_name,
    insurer_name, base_premium, and deductible.

    Use this tool whenever the user mentions a car brand, model name, or sub-model.
    IMPORTANT: Split the car name into separate arguments.
    Example: "Honda Civic e:HEV RS 2024" → brand="Honda", model="Civic", sub_model="e:HEV RS", year=2024
    Do NOT put the year inside sub_model.

    Args:
        brand: The car brand only (e.g., "Honda", "Toyota", "BMW").
        model: The car model only (e.g., "Civic", "Camry", "Tank"). Do NOT include brand here.
        sub_model: The trim/sub-model only (e.g., "Type R", "e:HEV RS", "Hybrid Premium"). Do NOT include year here.
        year: The manufacturing year as an integer (e.g., 2024).
    """
    logger.info("🔍 [QUOTATION SEARCH] Starting vehicle search")
    logger.info(f"   Brand: {brand}")
    logger.info(f"   Model: {model}")
    logger.info(f"   Sub-model: {sub_model}")
    logger.info(f"   Year: {year}")
    
    if not any([brand, model, sub_model, year]):
        logger.warning("⚠️  [QUOTATION SEARCH] No search parameters provided")
        return json.dumps({"result": "Error: You must provide at least one of brand, model, sub_model, or year."})

    # Clean year accidentally put into sub_model by LLM
    if sub_model:
        original_sub_model = sub_model
        sub_model = _clean_sub_model(sub_model)
        if original_sub_model != sub_model:
            logger.info(f"   Cleaned sub_model: '{original_sub_model}' → '{sub_model}'")

    client = get_supabase_client()

    def _run_query(b, m, s, y):
        q = client.table("vw_quotation_details").select("*")
        if b:
            q = q.ilike("brand", f"%{b}%")
        if m:
            q = q.ilike("model", f"%{m}%")
        if s:
            q = q.ilike("sub_model", f"%{s}%")
        if y:
            q = q.eq("year", y)
        return q.execute().data

    # Attempt 1: Full exact search
    logger.info("🎯 [ATTEMPT 1] Exact match search (all parameters)")
    data = _run_query(brand, model, sub_model, year)
    if data:
        logger.info(f"✅ [SUCCESS] Found {len(data)} exact matches")
        return json.dumps({"result": "Found quotation details.", "records": data})

    # Attempt 2: Drop year constraint
    if year:
        logger.info("🎯 [ATTEMPT 2] Relaxing year constraint")
        data = _run_query(brand, model, sub_model, None)
        if data:
            logger.info(f"✅ [SUCCESS] Found {len(data)} matches (year relaxed)")
            return json.dumps({"result": "Found quotation details (year relaxed).", "records": data})

    # Attempt 3: Drop sub_model constraint
    if sub_model:
        logger.info("🎯 [ATTEMPT 3] Relaxing sub_model constraint")
        data = _run_query(brand, model, None, year)
        if data:
            logger.info(f"✅ [SUCCESS] Found {len(data)} matches (sub_model relaxed)")
            return json.dumps({
                "result": f"No exact match for sub_model '{sub_model}'. Here are available trims — pick the closest one.",
                "records": data,
            })

    # Attempt 4: Brand + model only
    if brand or model:
        logger.info("🎯 [ATTEMPT 4] Brand + model only")
        data = _run_query(brand, model, None, None)
        if data:
            logger.info(f"✅ [SUCCESS] Found {len(data)} matches (brand+model only)")
            return json.dumps({
                "result": f"Could not match '{sub_model or ''}' trim. Here are all available variants for {brand or ''} {model or ''}.",
                "records": data,
            })

    # Attempt 5: Brand only
    if brand:
        logger.info("🎯 [ATTEMPT 5] Brand only")
        data = _run_query(brand, None, None, None)
        if data:
            logger.info(f"✅ [SUCCESS] Found {len(data)} matches (brand only)")
            return json.dumps({
                "result": f"Could not find exact model. Here are all available {brand} vehicles.",
                "records": data,
            })

    # Last resort: return full catalogue
    logger.warning("⚠️  [ATTEMPT 6] No matches found, returning full catalogue")
    all_data = client.table("vw_quotation_details").select("brand, model, sub_model, year").execute().data
    logger.info(f"📋 [CATALOGUE] Returning {len(all_data)} total vehicles")
    return json.dumps({
        "result": "No matching vehicle found. Here is the full catalogue to help you select the correct car.",
        "records": all_data,
    })
