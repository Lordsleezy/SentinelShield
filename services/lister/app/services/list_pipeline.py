import logging
import re
from typing import Any
from urllib.parse import urlparse

from app.models import GeneratedListing, ListResponse
from app.services.crawl4ai_extract import extract_product_data
from app.services.ollama import generate_listing
from app.services.serper import find_cheapest_source
from app.services.supabase_client import get_store

logger = logging.getLogger(__name__)


def _is_url(text: str) -> bool:
    return bool(re.match(r"^https?://", text.strip(), re.I))


def _is_facebook_url(url: str) -> bool:
    host = urlparse(url).netloc.lower()
    return host == "facebook.com" or host.endswith(".facebook.com") or host == "fb.com" or host.endswith(".fb.com")


def _request_value(request_data: dict[str, Any], key: str, default: Any = "") -> Any:
    value = request_data.get(key, default)
    return default if value is None else value


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


async def build_listing(user_input: str | dict[str, Any]) -> ListResponse:
    request_data = user_input if isinstance(user_input, dict) else {"input": user_input}
    user_input = str(
        _request_value(request_data, "input")
        or _request_value(request_data, "url")
        or _request_value(request_data, "title")
    ).strip()
    source_url = user_input
    retailer = ""
    serper_price = 0.0

    explicit_url = str(_request_value(request_data, "url")).strip()
    if explicit_url:
        source_url = explicit_url

    if explicit_url:
        from app.services.crawl4ai_extract import _extract_retailer
        retailer = _extract_retailer(explicit_url)
    elif not _is_url(user_input):
        logger.info("Resolving cheapest source for: %s", user_input)
        source_url, serper_price, retailer = await find_cheapest_source(user_input)
    else:
        from app.services.crawl4ai_extract import _extract_retailer
        retailer = _extract_retailer(user_input)

    if _is_facebook_url(source_url):
        extracted = await _extract_from_scout_data(source_url, request_data, user_input)
    else:
        extracted = await extract_product_data(source_url, fallback_name=user_input)

    # If Serper returned a Google Shopping page, follow the retailer link found in extraction
    retailer_url = _find_retailer_url(extracted)
    if retailer_url and retailer_url != source_url and not _is_facebook_url(retailer_url):
        logger.info("Re-extracting from retailer URL: %s", retailer_url)
        source_url = retailer_url
        retailer_data = await extract_product_data(retailer_url, fallback_name=extracted.get("title", user_input))
        if retailer_data.get("title") and "google" not in retailer_data.get("title", "").lower():
            extracted = retailer_data
    if serper_price and not extracted.get("price"):
        extracted["price"] = serper_price
    if retailer and not _is_facebook_url(source_url):
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


async def _extract_from_scout_data(source_url: str, request_data: dict[str, Any], fallback_name: str) -> dict[str, Any]:
    store = get_store()
    approval = await store.get_scout_approval_by_url(source_url)
    title = request_data.get("title") or (approval or {}).get("title") or fallback_name
    price = request_data.get("price")
    if price in (None, ""):
        price = (approval or {}).get("price") or 0.0
    image = request_data.get("image") or (approval or {}).get("image") or ""
    images = [image] if image else []
    description = (approval or {}).get("reasoning") or ""
    return {
        "source_url": source_url,
        "title": title,
        "description": description,
        "specs": {},
        "images": images,
        "price": float(price or 0.0),
        "retailer": "facebook_marketplace",
        "availability": "unknown",
        "raw_markdown": "",
        "source": request_data.get("source") or (approval or {}).get("source") or "facebook_marketplace",
        "approval_id": request_data.get("approval_id") or (approval or {}).get("id") or "",
    }
