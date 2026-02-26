import json
from langchain_core.tools import tool
from database import get_supabase_client

@tool
def search_quotation_details(query: str) -> str:
    """
    Search the vw_quotation_details view for vehicle information and insurance premiums.
    Returns brand, model, sub_model, year, car_estimated_price, plan_type, plan_name, 
    insurer_name, base_premium, and deductible.
    
    Use this tool whenever the user mentions a car brand, model name, or sub-model
    to retrieve the exact insurance quotation data.

    Args:
        query: A search term (e.g., "Honda", "Civic", "Type R", "Tank").
    """
    client = get_supabase_client()
    
    # Try searching by model
    model_resp = client.table("vw_quotation_details").select("*").ilike("model", f"%{query}%").execute()
    if model_resp.data:
        return json.dumps({"result": "Found quotation details.", "records": model_resp.data})

    # Try sub_model
    sub_model_resp = client.table("vw_quotation_details").select("*").ilike("sub_model", f"%{query}%").execute()
    if sub_model_resp.data:
        return json.dumps({"result": "Found quotation details.", "records": sub_model_resp.data})

    # Try brand
    brand_resp = client.table("vw_quotation_details").select("*").ilike("brand", f"%{query}%").execute()
    if brand_resp.data:
        return json.dumps({"result": "Found quotation details.", "records": brand_resp.data})

    return json.dumps({"result": "No matching quotation details found.", "records": []})
