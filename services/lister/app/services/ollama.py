import json
import logging
import re

import httpx

from app.config import get_settings
from app.models import GeneratedListing

logger = logging.getLogger(__name__)

LISTING_PROMPT = """You are an expert ecommerce copywriter. Given extracted product data, generate a clean professional listing.

Return ONLY valid JSON with this structure:
{{
  "title": "compelling product title (max 80 chars)",
  "description": "2-3 sentence product description",
  "features": ["bullet 1", "bullet 2", ... max 5 bullets],
  "suggested_price": <number in USD>
}}

Make it sound professional and appealing for an online store.

Product data:
{product_json}
"""


async def generate_listing(extracted: dict) -> GeneratedListing:
    settings = get_settings()
    prompt = LISTING_PROMPT.format(product_json=json.dumps(extracted, indent=2)[:4000])

    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(
            f"{settings.ollama_host.rstrip('/')}/api/generate",
            json={
                "model": settings.ollama_model,
                "prompt": prompt,
                "stream": False,
                "format": "json",
            },
        )
        resp.raise_for_status()
        raw = resp.json().get("response", "")

    parsed = _parse_json(raw)
    price = float(parsed.get("suggested_price") or extracted.get("price") or 0)
    features = parsed.get("features", [])
    if isinstance(features, str):
        features = [features]
    features = [str(f) for f in features[:5]]

    listing = GeneratedListing(
        title=str(parsed.get("title") or extracted.get("title", "Product")),
        description=str(parsed.get("description") or extracted.get("description", "")),
        features=features,
        suggested_price=price,
    )
    logger.info("Generated listing: %s ($%.2f)", listing.title, listing.suggested_price)
    return listing


def _parse_json(raw: str) -> dict:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", raw)
        if match:
            try:
                return json.loads(match.group())
            except json.JSONDecodeError:
                pass
    logger.warning("Failed to parse Ollama listing JSON")
    return {}
