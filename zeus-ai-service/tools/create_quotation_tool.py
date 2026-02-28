import json
import uuid
from datetime import datetime, timedelta
from typing import Optional
from langchain_core.tools import tool
from database import get_supabase_client


def _generate_quotation_number() -> str:
    """Generate a unique quotation number in format QT-YYYYMMDD-XXXX"""
    timestamp = datetime.now().strftime("%Y%m%d")
    random_suffix = str(uuid.uuid4())[:4].upper()
    return f"QT-{timestamp}-{random_suffix}"


@tool
def create_quotation(
    session_id: str,
    car_model_id: int,
    plan_id: int,
    customer_name: Optional[str] = None,
    customer_email: Optional[str] = None,
    customer_phone: Optional[str] = None,
) -> str:
    """
    Create and save an official insurance quotation after the customer has selected their preferred plan.
    This tool should ONLY be called after the user has explicitly chosen a specific car and insurance plan.
    
    Use this tool when:
    - The user says they want to proceed with a specific plan
    - The user asks to "create a quotation" or "generate a quote"
    - The user wants to save their selection
    
    Args:
        session_id: The current chat session ID (UUID string)
        car_model_id: The ID of the selected car model from vw_quotation_details
        plan_id: The ID of the selected insurance plan from vw_quotation_details
        customer_name: Optional customer name
        customer_email: Optional customer email for sending the quotation
        customer_phone: Optional customer phone number
    
    Returns:
        A JSON string with the created quotation details including quotation number and validity period.
    """
    print(f"\n[CREATE QUOTATION] Starting quotation creation for session {session_id}")
    print(f"[CREATE QUOTATION] Car Model ID: {car_model_id}, Plan ID: {plan_id}")
    
    client = get_supabase_client()
    
    # Fetch the quotation details from the view
    quotation_data = client.table("vw_quotation_details").select("*").eq("car_model_id", car_model_id).eq("plan_id", plan_id).execute()
    
    if not quotation_data.data or len(quotation_data.data) == 0:
        print("[CREATE QUOTATION] ERROR: No matching car/plan combination found")
        return json.dumps({
            "result": "Error: Could not find the selected car and plan combination. Please verify the IDs.",
            "success": False
        })
    
    details = quotation_data.data[0]
    print(f"[CREATE QUOTATION] Found details: {details['brand']} {details['model']} {details['sub_model']} - {details['plan_name']}")
    
    # Generate quotation number and validity
    quotation_number = _generate_quotation_number()
    valid_until = datetime.now() + timedelta(days=30)  # Valid for 30 days
    
    # Calculate total premium (base premium is the total for now, can add taxes/fees later)
    total_premium = float(details['base_premium'])
    
    # Create quotation record
    quotation_record = {
        "session_id": session_id,
        "car_model_id": car_model_id,
        "plan_id": plan_id,
        "customer_name": customer_name,
        "customer_email": customer_email,
        "customer_phone": customer_phone,
        "car_estimated_price": float(details['car_estimated_price']),
        "base_premium": float(details['base_premium']),
        "deductible": float(details['deductible']),
        "total_premium": total_premium,
        "quotation_number": quotation_number,
        "valid_until": valid_until.isoformat(),
        "status": "draft"
    }
    
    print(f"[CREATE QUOTATION] Inserting quotation record: {quotation_number}")
    
    try:
        insert_response = client.table("quotations").insert(quotation_record).execute()
        
        if not insert_response.data:
            print("[CREATE QUOTATION] ERROR: Failed to insert quotation")
            return json.dumps({
                "result": "Error: Failed to create quotation. Please try again.",
                "success": False
            })
        
        created_quotation = insert_response.data[0]
        print(f"[CREATE QUOTATION] SUCCESS: Quotation created with ID {created_quotation['id']}")
        
        return json.dumps({
            "result": "Quotation created successfully!",
            "success": True,
            "quotation": {
                "quotation_id": str(created_quotation['id']),
                "quotation_number": quotation_number,
                "vehicle": f"{details['brand']} {details['model']} {details['sub_model']} ({details['year']})",
                "vehicle_price": float(details['car_estimated_price']),
                "plan_type": details['plan_type'],
                "plan_name": details['plan_name'],
                "insurer": details['insurer_name'],
                "annual_premium": float(details['base_premium']),
                "deductible": float(details['deductible']),
                "total_premium": total_premium,
                "valid_until": valid_until.strftime("%Y-%m-%d"),
                "customer_name": customer_name,
                "customer_email": customer_email,
                "customer_phone": customer_phone,
                "status": "draft"
            }
        })
    
    except Exception as e:
        print(f"[CREATE QUOTATION] EXCEPTION: {str(e)}")
        return json.dumps({
            "result": f"Error creating quotation: {str(e)}",
            "success": False
        })
