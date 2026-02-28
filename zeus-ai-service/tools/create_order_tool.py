import json
import uuid
from datetime import datetime, timedelta
from typing import Optional
from langchain_core.tools import tool
from database import get_supabase_client


def _generate_order_number() -> str:
    """Generate a unique order number in format ORD-YYYYMMDD-XXXX"""
    timestamp = datetime.now().strftime("%Y%m%d")
    random_suffix = str(uuid.uuid4())[:4].upper()
    return f"ORD-{timestamp}-{random_suffix}"


def _generate_policy_number() -> str:
    """Generate a unique policy number in format POL-YYYYMMDD-XXXX"""
    timestamp = datetime.now().strftime("%Y%m%d")
    random_suffix = str(uuid.uuid4())[:4].upper()
    return f"POL-{timestamp}-{random_suffix}"


@tool
def create_order(
    quotation_id: str,
    payment_method: Optional[str] = "pending",
) -> str:
    """
    Create an order from an accepted quotation to initiate the purchase process.
    This tool should be called when the customer confirms they want to purchase the insurance.
    
    Use this tool when:
    - The user says they want to "buy", "purchase", or "proceed with payment"
    - The user confirms the quotation and wants to complete the transaction
    - The user asks "how do I pay?" or "what's next?"
    
    Args:
        quotation_id: The UUID of the quotation to convert into an order
        payment_method: Payment method (e.g., "credit_card", "bank_transfer", "promptpay", "pending")
    
    Returns:
        A JSON string with the created order details including order number, payment instructions, and policy information.
    """
    print(f"\n[CREATE ORDER] Starting order creation for quotation {quotation_id}")
    
    client = get_supabase_client()
    
    # Fetch the quotation
    quotation_response = client.table("quotations").select("*").eq("id", quotation_id).execute()
    
    if not quotation_response.data or len(quotation_response.data) == 0:
        print(f"[CREATE ORDER] ERROR: Quotation {quotation_id} not found")
        return json.dumps({
            "result": "Error: Quotation not found. Please provide a valid quotation ID.",
            "success": False
        })
    
    quotation = quotation_response.data[0]
    print(f"[CREATE ORDER] Found quotation: {quotation['quotation_number']}")
    
    # Check if quotation is still valid
    valid_until = datetime.fromisoformat(quotation['valid_until'].replace('Z', '+00:00'))
    if datetime.now(valid_until.tzinfo) > valid_until:
        print(f"[CREATE ORDER] ERROR: Quotation expired on {valid_until}")
        return json.dumps({
            "result": f"Error: This quotation expired on {valid_until.strftime('%Y-%m-%d')}. Please request a new quotation.",
            "success": False
        })
    
    # Check if quotation status is appropriate
    if quotation['status'] == 'expired':
        return json.dumps({
            "result": "Error: This quotation has expired. Please request a new quotation.",
            "success": False
        })
    
    # Check if order already exists for this quotation
    existing_order = client.table("orders").select("*").eq("quotation_id", quotation_id).execute()
    if existing_order.data and len(existing_order.data) > 0:
        existing = existing_order.data[0]
        print(f"[CREATE ORDER] Order already exists: {existing['order_number']}")
        return json.dumps({
            "result": "An order already exists for this quotation.",
            "success": True,
            "order": {
                "order_id": str(existing['id']),
                "order_number": existing['order_number'],
                "quotation_number": quotation['quotation_number'],
                "payment_status": existing['payment_status'],
                "payment_method": existing['payment_method'],
                "total_amount": float(quotation['total_premium']),
                "policy_number": existing['policy_number'],
                "policy_status": existing['policy_status']
            }
        })
    
    # Generate order and policy numbers
    order_number = _generate_order_number()
    policy_number = _generate_policy_number()
    
    # Calculate policy dates (1 year from today)
    policy_start = datetime.now().date()
    policy_end = policy_start + timedelta(days=365)
    
    # Create order record
    order_record = {
        "quotation_id": quotation_id,
        "order_number": order_number,
        "payment_status": "pending" if payment_method == "pending" else "awaiting_confirmation",
        "payment_method": payment_method,
        "policy_number": policy_number,
        "policy_start_date": policy_start.isoformat(),
        "policy_end_date": policy_end.isoformat(),
        "policy_status": "inactive"  # Will become active after payment
    }
    
    print(f"[CREATE ORDER] Inserting order record: {order_number}")
    
    try:
        insert_response = client.table("orders").insert(order_record).execute()
        
        if not insert_response.data:
            print("[CREATE ORDER] ERROR: Failed to insert order")
            return json.dumps({
                "result": "Error: Failed to create order. Please try again.",
                "success": False
            })
        
        created_order = insert_response.data[0]
        
        # Update quotation status to 'accepted'
        client.table("quotations").update({"status": "accepted"}).eq("id", quotation_id).execute()
        
        print(f"[CREATE ORDER] SUCCESS: Order created with ID {created_order['id']}")
        
        # Prepare payment instructions based on method
        payment_instructions = {
            "credit_card": "Please proceed to the payment gateway to complete your credit card payment.",
            "bank_transfer": f"Please transfer {quotation['total_premium']} THB to:\nBank: Bangkok Bank\nAccount: 123-456-7890\nName: Zeus Insurance Co., Ltd.\nReference: {order_number}",
            "promptpay": f"Please scan the QR code or transfer to PromptPay ID: 0123456789\nAmount: {quotation['total_premium']} THB\nReference: {order_number}",
            "pending": "Payment method not selected. Please choose a payment method to proceed."
        }
        
        return json.dumps({
            "result": "Order created successfully!",
            "success": True,
            "order": {
                "order_id": str(created_order['id']),
                "order_number": order_number,
                "quotation_number": quotation['quotation_number'],
                "customer_name": quotation['customer_name'],
                "customer_email": quotation['customer_email'],
                "customer_phone": quotation['customer_phone'],
                "total_amount": float(quotation['total_premium']),
                "payment_status": created_order['payment_status'],
                "payment_method": payment_method,
                "payment_instructions": payment_instructions.get(payment_method, "Please contact support for payment instructions."),
                "policy_number": policy_number,
                "policy_start_date": policy_start.isoformat(),
                "policy_end_date": policy_end.isoformat(),
                "policy_status": "inactive (will activate upon payment confirmation)",
                "created_at": created_order['created_at']
            }
        })
    
    except Exception as e:
        print(f"[CREATE ORDER] EXCEPTION: {str(e)}")
        return json.dumps({
            "result": f"Error creating order: {str(e)}",
            "success": False
        })


@tool
def update_order_payment(
    order_id: str,
    payment_status: str,
    payment_date: Optional[str] = None,
) -> str:
    """
    Update the payment status of an order and activate the policy if payment is confirmed.
    This tool is typically used by admin/system to confirm payments.
    
    Use this tool when:
    - Payment has been confirmed/verified
    - Payment has failed and needs to be marked
    - Customer provides payment proof and you need to update status
    
    Args:
        order_id: The UUID of the order to update
        payment_status: New payment status ("paid", "failed", "refunded")
        payment_date: Optional ISO format date when payment was received
    
    Returns:
        A JSON string with the updated order status and policy activation details.
    """
    print(f"\n[UPDATE ORDER PAYMENT] Updating order {order_id} to status: {payment_status}")
    
    client = get_supabase_client()
    
    # Fetch the order
    order_response = client.table("orders").select("*").eq("id", order_id).execute()
    
    if not order_response.data or len(order_response.data) == 0:
        print(f"[UPDATE ORDER PAYMENT] ERROR: Order {order_id} not found")
        return json.dumps({
            "result": "Error: Order not found.",
            "success": False
        })
    
    order = order_response.data[0]
    print(f"[UPDATE ORDER PAYMENT] Found order: {order['order_number']}")
    
    # Prepare update data
    update_data = {
        "payment_status": payment_status,
        "updated_at": datetime.now().isoformat()
    }
    
    if payment_date:
        update_data["payment_date"] = payment_date
    elif payment_status == "paid":
        update_data["payment_date"] = datetime.now().isoformat()
    
    # If payment is confirmed, activate the policy
    if payment_status == "paid":
        update_data["policy_status"] = "active"
        print(f"[UPDATE ORDER PAYMENT] Activating policy {order['policy_number']}")
    
    try:
        update_response = client.table("orders").update(update_data).eq("id", order_id).execute()
        
        if not update_response.data:
            print("[UPDATE ORDER PAYMENT] ERROR: Failed to update order")
            return json.dumps({
                "result": "Error: Failed to update order payment status.",
                "success": False
            })
        
        updated_order = update_response.data[0]
        print(f"[UPDATE ORDER PAYMENT] SUCCESS: Order updated")
        
        result_message = "Payment status updated successfully!"
        if payment_status == "paid":
            result_message += f" Policy {order['policy_number']} is now ACTIVE."
        
        return json.dumps({
            "result": result_message,
            "success": True,
            "order": {
                "order_id": str(updated_order['id']),
                "order_number": updated_order['order_number'],
                "payment_status": updated_order['payment_status'],
                "payment_date": updated_order.get('payment_date'),
                "policy_number": updated_order['policy_number'],
                "policy_status": updated_order['policy_status'],
                "policy_start_date": updated_order['policy_start_date'],
                "policy_end_date": updated_order['policy_end_date']
            }
        })
    
    except Exception as e:
        print(f"[UPDATE ORDER PAYMENT] EXCEPTION: {str(e)}")
        return json.dumps({
            "result": f"Error updating order: {str(e)}",
            "success": False
        })


@tool
def get_order_status(order_number: str) -> str:
    """
    Retrieve the current status of an order by order number.
    
    Use this tool when:
    - User asks "what's the status of my order?"
    - User wants to check payment status
    - User asks about their policy activation
    
    Args:
        order_number: The order number (format: ORD-YYYYMMDD-XXXX)
    
    Returns:
        A JSON string with the order details and current status.
    """
    print(f"\n[GET ORDER STATUS] Fetching status for order: {order_number}")
    
    client = get_supabase_client()
    
    # Fetch the order
    order_response = client.table("orders").select("*").eq("order_number", order_number).execute()
    
    if not order_response.data or len(order_response.data) == 0:
        print(f"[GET ORDER STATUS] ERROR: Order {order_number} not found")
        return json.dumps({
            "result": f"Order {order_number} not found. Please check the order number and try again.",
            "success": False
        })
    
    order = order_response.data[0]
    
    # Fetch related quotation
    quotation_response = client.table("quotations").select("*").eq("id", order['quotation_id']).execute()
    quotation = quotation_response.data[0] if quotation_response.data else {}
    
    print(f"[GET ORDER STATUS] Found order with status: {order['payment_status']}")
    
    return json.dumps({
        "result": "Order found.",
        "success": True,
        "order": {
            "order_number": order['order_number'],
            "quotation_number": quotation.get('quotation_number'),
            "customer_name": quotation.get('customer_name'),
            "total_amount": float(quotation.get('total_premium', 0)),
            "payment_status": order['payment_status'],
            "payment_method": order.get('payment_method'),
            "payment_date": order.get('payment_date'),
            "policy_number": order['policy_number'],
            "policy_status": order['policy_status'],
            "policy_start_date": order['policy_start_date'],
            "policy_end_date": order['policy_end_date'],
            "created_at": order['created_at']
        }
    })
