import asyncio
import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.config import get_settings
from app.services.search_pipeline import run_search
from app.services.supabase_client import get_store

logger = logging.getLogger(__name__)

_scheduler: AsyncIOScheduler | None = None


async def autonomous_scan() -> None:
    settings = get_settings()
    categories = [c.strip() for c in settings.scan_categories.split(",") if c.strip()]
    store = get_store()
    known_urls = await store.known_urls()

    total_found = 0
    total_qualifying = 0
    total_cards = 0

    logger.info("Starting autonomous scan across %d categories", len(categories))
    for category in categories:
        query = f"used {category} deal"
        try:
            results, cards = await run_search(
                query,
                max_results=10,
                create_approvals=True,
                skip_urls=known_urls,
            )
            total_found += len(results)
            total_qualifying += len(results)
            total_cards += cards
            for r in results:
                if r.url:
                    known_urls.add(r.url)
            logger.info("Scan category %r: %d qualifying, %d cards", category, len(results), cards)
        except Exception as exc:
            logger.error("Scan failed for %r: %s", category, exc)

    logger.info(
        "Autonomous scan complete: %d qualifying deals, %d new approval cards",
        total_qualifying,
        total_cards,
    )


def _run_scan_job() -> None:
    asyncio.get_event_loop().create_task(autonomous_scan())


def start_scheduler() -> AsyncIOScheduler:
    global _scheduler
    if _scheduler is not None:
        return _scheduler

    _scheduler = AsyncIOScheduler()
    _scheduler.add_job(
        autonomous_scan,
        CronTrigger(hour=2, minute=0),
        id="scout_daily_scan",
        replace_existing=True,
        misfire_grace_time=3600,
    )
    _scheduler.start()
    logger.info("Scheduler started — daily scan at 02:00")
    return _scheduler


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler:
        _scheduler.shutdown(wait=False)
        _scheduler = None
