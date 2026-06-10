import logging
import re
from typing import Any

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)


def _parse_price(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    match = re.search(r"[\d,]+\.?\d*", str(value).replace(",", ""))
    return float(match.group()) if match else 0.0


async def find_cheapest_source(product_name: str) -> tuple[str, float, str]:
    """Return (url, price, retailer) for cheapest Serper shopping result."""
    settings = get_settings()
    if not settings.serper_api_key:
        raise ValueError("SERPER_API_KEY not configured")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            "https://google.serper.dev/shopping",
            json={"q": product_name, "num": 15},
            headers={
                "X-API-KEY": settings.serper_api_key,
                "Content-Type": "application/json",
            },
        )
        resp.raise_for_status()
        data = resp.json()

    items = data.get("shopping", [])
    if not items:
        raise ValueError(f"No shopping results for: {product_name}")

    def _score_item(item: dict) -> tuple[float, int]:
        price = _parse_price(item.get("price")) or float("inf")
        link = (item.get("link") or "").lower()
        # Prefer direct retailer URLs over Google Shopping redirect pages
        direct = 0 if "google.com" in link else 1
        return (price, -direct)

    ranked = sorted(items, key=_score_item)
    best = ranked[0]
    url = best.get("link", "")
    # Fall back to first direct retailer link if cheapest is a Google redirect
    if "google.com" in url.lower():
        for item in ranked:
            link = item.get("link", "")
            if link and "google.com" not in link.lower():
                best = item
                url = link
                break
    price = _parse_price(best.get("price"))
    retailer = best.get("source", "unknown")
    logger.info("Cheapest source for %r: %s @ $%.2f (%s)", product_name, url, price, retailer)
    return url, price, retailer
