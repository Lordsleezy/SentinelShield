import logging

import httpx

from app.config import get_settings
from app.models import ApprovalCard

logger = logging.getLogger(__name__)


async def trigger_lister(card: ApprovalCard) -> tuple[bool, str]:
    settings = get_settings()
    target = f"{settings.lister_url.rstrip('/')}/list"
    payload = {
        "title": card.title,
        "url": card.url,
        "price": card.price,
        "source": card.source,
        "approval_id": card.id,
    }
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(target, json=payload)
            if resp.status_code < 400:
                return True, resp.text[:200]
            return False, f"Lister returned {resp.status_code}: {resp.text[:200]}"
    except httpx.ConnectError:
        logger.warning("Lister not reachable at %s", target)
        return False, "Lister service not available"
    except Exception as exc:
        logger.error("Lister trigger failed: %s", exc)
        return False, str(exc)
