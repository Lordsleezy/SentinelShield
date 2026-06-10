import json
import logging
import re
from typing import Any

from app.config import get_settings

logger = logging.getLogger(__name__)


def _is_url(text: str) -> bool:
    return text.strip().startswith(("http://", "https://"))


def _parse_price(text: str) -> float:
    if not text:
        return 0.0
    match = re.search(r"[\d,]+\.?\d*", text.replace(",", ""))
    return float(match.group()) if match else 0.0


async def extract_product_data(url: str, fallback_name: str = "") -> dict[str, Any]:
    """Extract product data from URL using Crawl4AI."""
    try:
        from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig
    except ImportError:
        logger.error("crawl4ai not installed")
        return _fallback_extract(url, fallback_name)

    settings = get_settings()
    result_data: dict[str, Any] = {
        "source_url": url,
        "title": fallback_name,
        "description": "",
        "specs": {},
        "images": [],
        "price": 0.0,
        "retailer": "",
        "availability": "unknown",
        "raw_markdown": "",
    }

    browser_config = BrowserConfig(headless=True)
    run_config = CrawlerRunConfig(
        wait_until="domcontentloaded",
        page_timeout=30000,
    )

    try:
        async with AsyncWebCrawler(config=browser_config) as crawler:
            result = await crawler.arun(url=url, config=run_config)
            if not result.success:
                logger.warning("Crawl4AI failed for %s: %s", url, result.error_message)
                return _fallback_extract(url, fallback_name)

            markdown = result.markdown or ""
            result_data["raw_markdown"] = markdown[:8000]

            # Title from metadata or first heading
            metadata = result.metadata or {}
            result_data["title"] = (
                metadata.get("title")
                or metadata.get("og:title")
                or _extract_title_from_md(markdown)
                or fallback_name
            )
            result_data["description"] = (
                metadata.get("description")
                or metadata.get("og:description")
                or _extract_description_from_md(markdown)
            )
            result_data["images"] = _extract_images(metadata, markdown)
            result_data["price"] = _extract_price(markdown, metadata)
            result_data["retailer"] = _extract_retailer(url)
            result_data["specs"] = _extract_specs(markdown)
            result_data["availability"] = _extract_availability(markdown)

    except Exception as exc:
        logger.error("Crawl4AI extraction error: %s", exc)
        return _fallback_extract(url, fallback_name)

    logger.info("Extracted product: %s ($%.2f)", result_data["title"], result_data["price"])
    return result_data


def _extract_title_from_md(md: str) -> str:
    for line in md.split("\n"):
        if line.startswith("# "):
            return line[2:].strip()
    return ""


def _extract_description_from_md(md: str) -> str:
    lines = [l.strip() for l in md.split("\n") if l.strip() and not l.startswith("#")]
    return " ".join(lines[:3])[:500]


def _extract_images(metadata: dict, md: str) -> list[str]:
    images: list[str] = []
    if metadata.get("og:image"):
        images.append(metadata["og:image"])
    for match in re.finditer(r"!\[.*?\]\((https?://[^)]+)\)", md):
        images.append(match.group(1))
    return list(dict.fromkeys(images))[:10]


def _extract_price(md: str, metadata: dict) -> float:
    for pattern in [r"\$[\d,]+\.?\d*", r"USD\s*[\d,]+\.?\d*", r"price[\"']?\s*:\s*[\d.]+"]:
        match = re.search(pattern, md, re.I)
        if match:
            return _parse_price(match.group())
    return 0.0


def _extract_retailer(url: str) -> str:
    from urllib.parse import urlparse

    host = urlparse(url).netloc.lower()
    for name in ("ebay", "amazon", "walmart", "bestbuy", "newegg", "target"):
        if name in host:
            return name
    return host.replace("www.", "")


def _extract_specs(md: str) -> dict[str, str]:
    specs: dict[str, str] = {}
    for line in md.split("\n"):
        if ":" in line and len(line) < 120:
            parts = line.split(":", 1)
            if len(parts) == 2:
                k, v = parts[0].strip(), parts[1].strip()
                if k and v and len(k) < 40:
                    specs[k] = v
    return dict(list(specs.items())[:20])


def _extract_availability(md: str) -> str:
    lower = md.lower()
    if "in stock" in lower or "add to cart" in lower:
        return "in_stock"
    if "out of stock" in lower or "sold out" in lower:
        return "out_of_stock"
    return "unknown"


def _fallback_extract(url: str, name: str) -> dict[str, Any]:
    return {
        "source_url": url,
        "title": name or "Unknown Product",
        "description": "",
        "specs": {},
        "images": [],
        "price": 0.0,
        "retailer": _extract_retailer(url),
        "availability": "unknown",
        "raw_markdown": "",
    }
