import asyncio
import logging
import re
from typing import Callable
from urllib.parse import quote_plus, urljoin

from app.models import DealResult

logger = logging.getLogger(__name__)

PLATFORM_SEARCHES: list[tuple[str, str, Callable]] = []


def _parse_price(text: str) -> float:
    if not text:
        return 0.0
    match = re.search(r"[\d,]+\.?\d*", text.replace(",", ""))
    if match:
        try:
            return float(match.group().replace(",", ""))
        except ValueError:
            pass
    return 0.0


def _price_from_text(text: str) -> float:
    for match in re.finditer(r"\$\s*[\d,]+(?:\.\d{1,2})?", text or ""):
        price = _parse_price(match.group())
        if price > 0:
            return price
    return 0.0


async def scrape_all_platforms(query: str, max_per_platform: int = 5) -> list[DealResult]:
    try:
        from playwright.async_api import async_playwright
        from playwright_stealth import Stealth
    except ImportError:
        logger.error("Playwright not installed")
        return []

    deals: list[DealResult] = []
    searches = [
        ("ebay", f"https://www.ebay.com/sch/i.html?_nkw={quote_plus(query)}&_sop=15"),
        (
            "facebook_marketplace",
            f"https://www.facebook.com/marketplace/search/?query={quote_plus(query)}",
        ),
        ("craigslist", f"https://www.craigslist.org/search/sss?query={quote_plus(query)}"),
        ("liquidation.com", f"https://www.liquidation.com/search?q={quote_plus(query)}"),
        ("bstock.com", f"https://bstock.com/search?q={quote_plus(query)}"),
        ("govplanet.com", f"https://www.govplanet.com/search?kw={quote_plus(query)}"),
    ]

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
            viewport={"width": 1280, "height": 800},
        )
        stealth = Stealth()
        await stealth.apply_stealth_async(context)

        for source, url in searches:
            try:
                platform_deals = await _scrape_page(
                    context, source, url, query, max_per_platform
                )
                deals.extend(platform_deals)
                logger.info("%s: scraped %d deals", source, len(platform_deals))
            except Exception as exc:
                logger.warning("%s scrape failed: %s", source, exc)
            await asyncio.sleep(1)

        await browser.close()

    return deals


async def _scrape_page(context, source: str, url: str, query: str, limit: int) -> list[DealResult]:
    page = await context.new_page()
    deals: list[DealResult] = []
    try:
        await page.goto(url, wait_until="domcontentloaded", timeout=25000)
        await page.wait_for_timeout(2000)

        if source == "ebay":
            deals = await _parse_ebay(page, limit)
        elif source == "craigslist":
            deals = await _parse_craigslist(page, limit)
        elif source == "facebook_marketplace":
            deals = await _parse_facebook_marketplace(page, limit)
        else:
            deals = await _parse_generic_listings(page, source, limit, "a[href*='product'], a[href*='item'], .product-card a")
    finally:
        await page.close()

    for d in deals:
        if not d.title:
            d.title = query
    return deals[:limit]


async def _parse_ebay(page, limit: int) -> list[DealResult]:
    deals = []
    items = await page.query_selector_all("li.s-item")
    for item in items[: limit + 2]:
        title_el = await item.query_selector(".s-item__title")
        price_el = await item.query_selector(".s-item__price")
        link_el = await item.query_selector("a.s-item__link")
        img_el = await item.query_selector("img.s-item__image-img")

        title = (await title_el.inner_text()) if title_el else ""
        if not title or "Shop on eBay" in title:
            continue
        price_text = (await price_el.inner_text()) if price_el else "0"
        href = (await link_el.get_attribute("href")) if link_el else ""
        img = (await img_el.get_attribute("src")) if img_el else ""
        price = _parse_price(price_text)

        deals.append(
            DealResult(
                title=title.strip(),
                price=price,
                market_value=price * 1.2,
                source="ebay",
                url=href or "",
                image=img or "",
                condition="used",
            )
        )
    return deals[:limit]


async def _parse_craigslist(page, limit: int) -> list[DealResult]:
    deals = []
    items = await page.query_selector_all("li.cl-static-search-result, li.result-row")
    for item in items[:limit]:
        title_el = await item.query_selector("a")
        price_el = await item.query_selector(".priceinfo, .result-price")
        title = (await title_el.inner_text()) if title_el else ""
        href = (await title_el.get_attribute("href")) if title_el else ""
        price_text = (await price_el.inner_text()) if price_el else "0"
        price = _parse_price(price_text)
        if href and not href.startswith("http"):
            href = f"https://www.craigslist.org{href}"
        deals.append(
            DealResult(
                title=title.strip(),
                price=price,
                market_value=price * 1.15,
                source="craigslist",
                url=href or "",
                condition="used",
            )
        )
    return deals


async def _parse_facebook_marketplace(page, limit: int) -> list[DealResult]:
    deals = []
    selector = "a[href*='/marketplace/item/']"
    try:
        await page.wait_for_selector(selector, timeout=10000)
    except Exception:
        logger.warning("Facebook Marketplace item selector not found")

    links = await page.query_selector_all(selector)
    html = await page.content()
    fallback_prices = [_parse_price(m.group()) for m in re.finditer(r"\$\s*[\d,]+(?:\.\d{1,2})?", html)]
    fallback_prices = [p for p in fallback_prices if p > 0]

    seen_urls: set[str] = set()
    for link in links:
        if len(deals) >= limit:
            break
        href = (await link.get_attribute("href")) or ""
        href = urljoin("https://www.facebook.com", href)
        if not href or href in seen_urls:
            continue
        seen_urls.add(href)

        card = await link.evaluate_handle(
            """(node) => {
                let current = node;
                for (let i = 0; i < 5 && current?.parentElement; i += 1) {
                    current = current.parentElement;
                }
                return current || node;
            }"""
        )
        text = ((await card.as_element().inner_text()) if card.as_element() else await link.inner_text()) or ""
        title = " ".join(line.strip() for line in text.splitlines() if line.strip() and "$" not in line)
        price = _price_from_text(text)
        if price == 0.0 and fallback_prices:
            price = fallback_prices[min(len(deals), len(fallback_prices) - 1)]

        if not title:
            title = (await link.inner_text()) or "Facebook Marketplace item"
        deals.append(
            DealResult(
                title=title.strip()[:200],
                price=price,
                market_value=price * 1.15 if price else 0.0,
                source="facebook_marketplace",
                url=href,
                condition="used",
            )
        )
    return deals


async def _parse_generic_listings(page, source: str, limit: int, selector: str) -> list[DealResult]:
    deals = []
    links = await page.query_selector_all(selector)
    for link in links[:limit]:
        title = (await link.inner_text()) or ""
        href = (await link.get_attribute("href")) or ""
        if href and not href.startswith("http"):
            href = f"https://{source.replace('_', '.')}{href}" if href.startswith("/") else href
        if not title.strip():
            continue
        deals.append(
            DealResult(
                title=title.strip()[:200],
                price=0.0,
                market_value=0.0,
                source=source,
                url=href,
                condition="unknown",
            )
        )
    return deals
