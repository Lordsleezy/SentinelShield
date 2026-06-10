import logging
import re

from app.models import GeneratedListing, ListResponse
from app.services.crawl4ai_extract import extract_product_data
from app.services.ollama import generate_listing
from app.services.serper import find_cheapest_source
from app.services.supabase_client import get_store

logger = logging.getLogger(__name__)


def _is_url(text: str) -> bool:
    return bool(re.match(r"^https?://", text.strip(), re.I))


def _find_retailer_url(extracted: dict) -> str:
    """Pull first direct retailer link from crawled Google Shopping markdown."""
    raw = extracted.get("raw_markdown", "") or ""
    for pattern in (
        r"https?://(?:www\.)?ebay\.com/itm/\d+[^\s\)\]\"]*",
        r"https?://(?:www\.)?amazon\.com/[^\s\)\]\"]+",
        r"https?://(?:www\.)?walmart\.com/ip/[^\s\)\]\"]+",
        r"https?://(?:www\.)?newegg\.com/[^\s\)\]\"]+",
    ):
        match = re.search(pattern, raw)
        if match:
            return match.group(0).rstrip(")")
    return ""


async def build_listing(user_input: str) -> ListResponse:
    user_input = user_input.strip()
    source_url = user_input
    retailer = ""
    serper_price = 0.0

    if not _is_url(user_input):
        logger.info("Resolving cheapest source for: %s", user_input)
        source_url, serper_price, retailer = await find_cheapest_source(user_input)
    else:
        from app.services.crawl4ai_extract import _extract_retailer
        retailer = _extract_retailer(user_input)

    extracted = await extract_product_data(source_url, fallback_name=user_input)

    # If Serper returned a Google Shopping page, follow the retailer link found in extraction
    retailer_url = _find_retailer_url(extracted)
    if retailer_url and retailer_url != source_url:
        logger.info("Re-extracting from retailer URL: %s", retailer_url)
        source_url = retailer_url
        retailer_data = await extract_product_data(retailer_url, fallback_name=extracted.get("title", user_input))
        if retailer_data.get("title") and "google" not in retailer_data.get("title", "").lower():
            extracted = retailer_data
    if serper_price and not extracted.get("price"):
        extracted["price"] = serper_price
    if retailer:
        extracted["retailer"] = retailer

    listing = await generate_listing(extracted)

    store = get_store()
    draft = await store.create_draft(
        user_input=user_input,
        source_url=source_url,
        extracted=extracted,
        listing=listing,
        retailer=extracted.get("retailer", retailer),
    )

    if not draft:
        # Return in-memory draft if Supabase unavailable
        from app.models import DraftListing
        from uuid import uuid4
        draft = DraftListing(
            id=str(uuid4()),
            input=user_input,
            source_url=source_url,
            title=listing.title,
            description=listing.description,
            features=listing.features,
            images=extracted.get("images", []),
            price=listing.suggested_price,
            retailer=extracted.get("retailer", ""),
            raw_extract=extracted,
            generated_listing=listing.model_dump(),
            status="pending",
        )

    return ListResponse(draft=draft, preview=listing)
