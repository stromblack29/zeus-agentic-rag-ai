import json
from typing import Optional
from langchain_core.tools import tool
from database import get_supabase_client

@tool
def search_quotation_details(brand: Optional[str] = None, model: Optional[str] = None, sub_model: Optional[str] = None, year: Optional[int] = None) -> str:
    """
    Search the vw_quotation_details view for vehicle information and insurance premiums.
    Returns brand, model, sub_model, year, car_estimated_price, plan_type, plan_name, 
    insurer_name, base_premium, and deductible.
    
    Use this tool whenever the user mentions a car brand, model name, or sub-model
    to retrieve the exact insurance quotation data. Extract the specific parts of the car name into the arguments.

    Args:
        brand: The car brand (e.g., "Honda", "Toyota").
        model: The car model (e.g., "Civic", "Tank", "D-Max").
        sub_model: The car sub-model or trim (e.g., "Type R", "e:HEV RS", "300 Hi-Torq"). Do NOT include the year in this field.
        year: The manufacturing year of the car (e.g., 2024).
    """
    if not brand and not model and not sub_model and not year:
        return json.dumps({"result": "Error: You must provide at least one of brand, model, sub_model, or year."})

    print(f"[TOOL CALL] search_quotation_details: brand={brand}, model={model}, sub_model={sub_model}, year={year}")

    client = get_supabase_client()
    query = client.table("vw_quotation_details").select("*")
    
    if brand:
        query = query.ilike("brand", f"%{brand}%")
    if model:
        query = query.ilike("model", f"%{model}%")
    if sub_model:
        # Sometimes LLMs pass "rs 2024" into sub_model. Strip digits if possible or rely on the fallback.
        query = query.ilike("sub_model", f"%{sub_model}%")
    if year:
        query = query.eq("year", year)

    resp = query.execute()
    
    if resp.data:
        return json.dumps({"result": "Found quotation details.", "records": resp.data})

    # Fallback 1: Broad search without sub_model and year
    if sub_model or year:
        fallback_query = client.table("vw_quotation_details").select("*")
        if brand:
            fallback_query = fallback_query.ilike("brand", f"%{brand}%")
        if model:
            fallback_query = fallback_query.ilike("model", f"%{model}%")
            
        fallback_resp = fallback_query.execute()
        if fallback_resp.data:
            return json.dumps({
                "result": f"No exact match found, but found these related models. Please check if any of these match what the user wants.", 
                "records": fallback_resp.data
            })

    # Fallback 2: If model was too specific (e.g. "Honda Civic"), just search by brand
    if brand:
        brand_resp = client.table("vw_quotation_details").select("*").ilike("brand", f"%{brand}%").execute()
        if brand_resp.data:
            return json.dumps({
                "result": f"Could not find exact model '{model}', but here are all '{brand}' vehicles available. Find the closest match.",
                "records": brand_resp.data
            })

    # Fallback 3: Return everything if we really can't find anything
    all_resp = client.table("vw_quotation_details").select("brand, model, sub_model, year").execute()
    return json.dumps({
        "result": "No matching quotation details found. Here is a list of all available cars in the database to help you find the right one.", 
        "records": all_resp.data
    })
