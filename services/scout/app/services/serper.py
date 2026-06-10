import logging
from typing import Any

import httpx

from app.config import get_settings
from app.models import DealResult

logger = logging.getLogger(__name__)


def _parse_price(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).replace("$", "").replace(",", "").strip()
    try:
        return float(text)
    except ValueError:
        return 0.0


async def search_google_shopping(query: str, max_results: int = 10) -> list[DealResult]:
    settings = get_settings()
    key = settings.serper_api_key
    if not key:
        logger.warning("SERPER_API_KEY not set — skipping Google Shopping")
        return []

    payload = {"q": query, "num": max_results}
    headers = {"X-API-KEY": key, "Content-Type": "application/json"}
    logger.info(
        "Serper request: POST https://google.serper.dev/shopping q=%r num=%d key_len=%d",
        query,
        max_results,
        len(key),
    )

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            "https://google.serper.dev/shopping",
            json=payload,
            headers=headers,
        )
        raw_text = resp.text
        logger.info("Serper response: HTTP %s body_len=%d", resp.status_code, len(raw_text))
        if resp.status_code >= 400:
            logger.error("Serper error body: %s", raw_text[:500])
        resp.raise_for_status()
        data = resp.json()

    shopping = data.get("shopping", [])
    logger.info(
        "Serper parsed: shopping=%d credits=%s sample_titles=%s",
        len(shopping),
        data.get("credits"),
        [item.get("title", "")[:40] for item in shopping[:3]],
    )

    deals: list[DealResult] = []
    for item in shopping[:max_results]:
        price = _parse_price(item.get("price"))
        market = _parse_price(item.get("price")) or price
        deals.append(
            DealResult(
                title=item.get("title", "Unknown"),
                price=price,
                market_value=market * 1.15 if market else price,
                source=item.get("source", "google_shopping"),
                url=item.get("link", ""),
                image=item.get("imageUrl", item.get("thumbnail", "")),
                condition="new",
            )
        )
    logger.info("Serper returned %d shopping results for %r", len(deals), query)
    return deals
