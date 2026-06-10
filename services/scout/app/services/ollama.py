import json
import logging
import re

import httpx

from app.config import get_settings
from app.models import DealResult, ScoredDeal

logger = logging.getLogger(__name__)

SCORE_PROMPT = """You are a resale deal analyst. Score each product deal from 1-10 based on:
- Price vs estimated market value (lower price vs market = higher score)
- Condition
- Resale potential on Sentinel Market

Return ONLY a valid JSON array. Each element must have:
{{"index": <int>, "score": <float 1-10>, "reasoning": "<brief explanation>", "market_value": <estimated resale market value as number>}}

Deals to score:
{deals_json}
"""


async def score_deals(deals: list[DealResult]) -> list[ScoredDeal]:
    if not deals:
        return []

    settings = get_settings()
    deals_payload = [
        {
            "index": i,
            "title": d.title,
            "price": d.price,
            "market_value": d.market_value,
            "source": d.source,
            "condition": d.condition,
            "url": d.url,
        }
        for i, d in enumerate(deals)
    ]

    prompt = SCORE_PROMPT.format(deals_json=json.dumps(deals_payload, indent=2))

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
        body = resp.json()
        raw = body.get("response", "")

    scores = _parse_scores(raw, len(deals))
    scored: list[ScoredDeal] = []
    for i, deal in enumerate(deals):
        info = scores.get(i, {"score": 5.0, "reasoning": "Default score", "market_value": deal.market_value})
        scored.append(
            ScoredDeal(
                title=deal.title,
                price=deal.price,
                market_value=float(info.get("market_value", deal.market_value)),
                source=deal.source,
                url=deal.url,
                image=deal.image,
                condition=deal.condition,
                score=float(info.get("score", 5)),
                reasoning=str(info.get("reasoning", "")),
            )
        )
    logger.info("Ollama scored %d deals", len(scored))
    return scored


def _parse_scores(raw: str, count: int) -> dict[int, dict]:
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict) and "deals" in parsed:
            parsed = parsed["deals"]
        if isinstance(parsed, dict):
            parsed = [parsed]
        result: dict[int, dict] = {}
        for item in parsed:
            idx = int(item.get("index", len(result)))
            result[idx] = item
        return result
    except json.JSONDecodeError:
        match = re.search(r"\[[\s\S]*\]", raw)
        if match:
            try:
                parsed = json.loads(match.group())
                return {int(item.get("index", i)): item for i, item in enumerate(parsed)}
            except json.JSONDecodeError:
                pass
    logger.warning("Failed to parse Ollama JSON, using defaults")
    return {i: {"score": 5.0, "reasoning": "Parse fallback", "market_value": 0} for i in range(count)}
