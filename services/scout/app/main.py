import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from app.config import get_settings
from app.logging_setup import setup_logging
from app.models import (
    ApproveResponse,
    ApprovalCard,
    RejectRequest,
    ScanResponse,
    SearchRequest,
    SearchResponse,
)
from app.scheduler import autonomous_scan, start_scheduler, stop_scheduler
from app.services.lister_client import trigger_lister
from app.services.search_pipeline import run_search
from app.services.supabase_client import get_store

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    settings = get_settings()
    store = get_store()
    await store.ensure_table()
    start_scheduler()
    logger.info("Scout FastAPI started on port %d", settings.port)
    yield
    stop_scheduler()
    logger.info("Scout shutting down")


app = FastAPI(
    title="Sentinel Scout",
    description="Live deal-finding AI for Sentinel Market",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "scout"}


@app.post("/search", response_model=SearchResponse)
async def search(body: SearchRequest):
    logger.info("POST /search query=%r max=%d", body.query, body.max_results)
    results, cards, qualifying = await run_search(body.query, body.max_results, create_approvals=True)
    return SearchResponse(
        query=body.query,
        total_found=len(results),
        qualifying=qualifying,
        results=results,
    )


@app.post("/scan", response_model=ScanResponse)
async def scan():
    logger.info("POST /scan — full autonomous scan triggered")
    settings = get_settings()
    categories = [c.strip() for c in settings.scan_categories.split(",") if c.strip()]
    store = get_store()
    known_urls = await store.known_urls()

    total_qualifying = 0
    total_cards = 0
    details: list[dict] = []

    for category in categories:
        query = f"used {category} deal"
        results, cards, qualifying = await run_search(
            query,
            max_results=10,
            create_approvals=True,
            skip_urls=known_urls,
        )
        total_qualifying += qualifying
        total_cards += cards
        for r in results:
            if r.url:
                known_urls.add(r.url)
        details.append({"category": category, "qualifying": qualifying, "cards": cards, "scored": len(results)})

    return ScanResponse(
        categories_scanned=len(categories),
        total_deals_found=total_qualifying,
        qualifying_deals=total_qualifying,
        new_approval_cards=total_cards,
        details=details,
    )


@app.get("/approvals", response_model=list[ApprovalCard])
async def approvals():
    store = get_store()
    if not store.configured:
        raise HTTPException(503, "Supabase not configured")
    return await store.list_pending()


@app.post("/approve/{approval_id}", response_model=ApproveResponse)
async def approve(approval_id: str):
    store = get_store()
    card = await store.get_by_id(approval_id)
    if not card:
        raise HTTPException(404, "Approval not found")
    updated = await store.update_status(approval_id, "approved")
    if not updated:
        raise HTTPException(500, "Failed to update approval")

    triggered, message = await trigger_lister(updated)
    logger.info("Approved %s — lister triggered=%s", approval_id, triggered)
    return ApproveResponse(
        id=approval_id,
        status="approved",
        lister_triggered=triggered,
        lister_message=message,
    )


@app.post("/reject/{approval_id}")
async def reject(approval_id: str, body: RejectRequest | None = None):
    store = get_store()
    card = await store.get_by_id(approval_id)
    if not card:
        raise HTTPException(404, "Approval not found")
    reason = body.reason if body else ""
    updated = await store.update_status(approval_id, "rejected", reason=reason)
    if not updated:
        raise HTTPException(500, "Failed to update approval")
    logger.info("Rejected %s reason=%r", approval_id, reason)
    return {"id": approval_id, "status": "rejected", "reason": reason}
