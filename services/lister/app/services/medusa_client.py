import base64
import logging
from typing import Any

import httpx

from app.config import get_settings
from app.models import DraftListing

logger = logging.getLogger(__name__)


def _headers() -> dict[str, str]:
    """Medusa v2 secret API keys use Basic auth (token as username, empty password)."""
    settings = get_settings()
    token = settings.medusa_api_key
    basic = base64.b64encode(f"{token}:".encode()).decode()
    return {
        "Authorization": f"Basic {basic}",
        "Content-Type": "application/json",
    }


async def verify_connection() -> tuple[bool, str]:
    settings = get_settings()
    if not settings.medusa_api_url or not settings.medusa_api_key:
        return False, "MEDUSA_API_URL or MEDUSA_API_KEY not set"
    url = f"{settings.medusa_api_url.rstrip('/')}/admin/products?limit=1"
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=_headers())
            if resp.status_code < 400:
                return True, f"OK (HTTP {resp.status_code})"
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"
    except Exception as exc:
        return False, str(exc)


async def create_product(draft: DraftListing) -> tuple[bool, str, str]:
    """Create product in Medusa. Returns (success, product_id, message)."""
    settings = get_settings()
    base = settings.medusa_api_url.rstrip("/")

    price_cents = int(round(draft.price * 100)) if draft.price else 0
    images = [{"url": u} for u in (draft.images or [])[:5] if u]

    # Medusa v2 product payload
    payload: dict[str, Any] = {
        "title": draft.title,
        "description": draft.description,
        "status": "published",
        "images": images,
        "options": [{"title": "Default", "values": ["Default"]}],
        "variants": [
            {
                "title": draft.title,
                "prices": [{"amount": price_cents, "currency_code": "usd"}],
                "options": {"Default": "Default"},
                "manage_inventory": False,
            }
        ],
    }

    if draft.features:
        payload["subtitle"] = "; ".join(draft.features[:3])

    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{base}/admin/products",
            headers=_headers(),
            json=payload,
        )
        if resp.status_code >= 400:
            # Retry simpler payload for API version differences
            logger.warning("Medusa create failed %s, retrying minimal payload", resp.status_code)
            simple = {
                "title": draft.title,
                "description": draft.description,
                "status": "published",
            }
            resp = await client.post(f"{base}/admin/products", headers=_headers(), json=simple)

        if resp.status_code >= 400:
            return False, "", f"Medusa error {resp.status_code}: {resp.text[:300]}"

        data = resp.json()
        product = data.get("product", data)
        product_id = product.get("id", "")
        logger.info("Created Medusa product %s: %s", product_id, draft.title)
        return True, product_id, "Product published"
