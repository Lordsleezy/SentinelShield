import logging

from app.config import get_settings
from app.models import DealResult, ScoredDeal
from app.services.ollama import score_deals
from app.services.scrapers import scrape_all_platforms
from app.services.serper import search_google_shopping
from app.services.supabase_client import get_store

logger = logging.getLogger(__name__)


def _dedupe_deals(deals: list[DealResult]) -> list[DealResult]:
    seen: set[str] = set()
    unique: list[DealResult] = []
    for d in deals:
        key = (d.url or d.title).lower().strip()
        if key and key not in seen:
            seen.add(key)
            unique.append(d)
    return unique


async def run_search(
    query: str,
    max_results: int = 10,
    *,
    create_approvals: bool = True,
    skip_urls: set[str] | None = None,
) -> tuple[list[ScoredDeal], int, int]:
    settings = get_settings()
    skip_urls = skip_urls or set()

    serper_deals = await search_google_shopping(query, max_results)
    scraped = await scrape_all_platforms(query, max_per_platform=max(3, max_results // 3))
    all_deals = _dedupe_deals(serper_deals + scraped)
    all_deals = [d for d in all_deals if d.url not in skip_urls][: max_results * 2]

    if not all_deals:
        logger.info("No deals found for %r", query)
        return [], 0, 0

    scored = await score_deals(all_deals)
    scored.sort(key=lambda deal: deal.score, reverse=True)
    qualifying = [d for d in scored if d.score >= settings.min_deal_score]
    logger.info(
        "Scored %d deals for %r — qualifying=%d (min_score=%.1f) top_scores=%s",
        len(scored),
        query,
        len(qualifying),
        settings.min_deal_score,
        [round(d.score, 1) for d in scored[:5]],
    )

    cards_created = 0
    if create_approvals:
        store = get_store()
        for deal in qualifying:
            if deal.url in skip_urls:
                continue
            card = await store.create_approval(deal)
            if card:
                cards_created += 1

    # /search returns top scored deals; min_deal_score only gates approval cards
    return scored[:max_results], cards_created, len(qualifying)
