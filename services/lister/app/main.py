import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.logging_setup import setup_logging
from app.models import (
    ApproveResponse,
    DraftListing,
    EditRequest,
    ListRequest,
    ListResponse,
    RejectRequest,
)
from app.services import medusa_client
from app.services.list_pipeline import build_listing
from app.services.supabase_client import get_store

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    store = get_store()
    if store.configured:
        await store.ensure_table()
    ok, msg = await medusa_client.verify_connection()
    logger.info("Medusa connection: %s — %s", ok, msg)
    yield


app = FastAPI(
    title="Sentinel Lister",
    description="On-demand AI product listing builder",
    version="1.0.0",
    lifespan=lifespan,
)

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    store = get_store()
    medusa_ok, medusa_msg = await medusa_client.verify_connection()
    return {
        "status": "ok",
        "service": "lister",
        "port": get_settings().port,
        "supabase_configured": store.configured,
        "medusa_connected": medusa_ok,
        "medusa_message": medusa_msg,
    }


@app.post("/list", response_model=ListResponse)
async def create_listing(req: ListRequest):
    request_data = req.model_dump()
    if not (req.input or req.url or req.title or "").strip():
        raise HTTPException(400, "input, url, or title is required")
    try:
        return await build_listing(request_data)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except Exception as exc:
        logger.exception("List pipeline failed")
        raise HTTPException(500, f"Listing failed: {exc}") from exc


@app.post("/list-all-approved")
async def list_all_approved():
    store = get_store()
    if not store.configured:
        raise HTTPException(503, "Supabase not configured")

    approvals = await store.list_unlisted_scout_approvals()
    processed = 0
    succeeded = 0
    failed = 0
    errors: list[dict[str, str]] = []

    for approval in approvals:
        processed += 1
        try:
            req = {
                "input": approval.get("url") or approval.get("title", ""),
                "title": approval.get("title", ""),
                "url": approval.get("url", ""),
                "price": approval.get("price"),
                "source": approval.get("source", ""),
                "approval_id": approval.get("id", ""),
                "image": approval.get("image", ""),
            }
            await build_listing(req)
            await store.mark_scout_approval_listed(str(approval.get("id", "")))
            succeeded += 1
        except Exception as exc:
            failed += 1
            logger.exception("Failed to list approval %s", approval.get("id"))
            errors.append({"id": str(approval.get("id", "")), "error": str(exc)})

    return {
        "processed": processed,
        "succeeded": succeeded,
        "failed": failed,
        "errors": errors[:20],
    }


@app.get("/drafts", response_model=list[DraftListing])
async def list_drafts():
    store = get_store()
    if not store.configured:
        raise HTTPException(503, "Supabase not configured — set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")
    return await store.list_pending()


@app.post("/approve/{draft_id}", response_model=ApproveResponse)
async def approve_draft(draft_id: str):
    store = get_store()
    if not store.configured:
        raise HTTPException(503, "Supabase not configured")
    draft = await store.get_by_id(draft_id)
    if not draft:
        raise HTTPException(404, "Draft not found")
    if draft.status not in ("pending", "approved"):
        raise HTTPException(400, f"Cannot approve draft with status: {draft.status}")

    ok, product_id, msg = await medusa_client.create_product(draft)
    if not ok:
        raise HTTPException(502, msg)

    updated = await store.update_status(
        draft_id,
        "published",
        {"medusa_product_id": product_id},
    )
    return ApproveResponse(
        id=draft_id,
        status=updated.status if updated else "published",
        medusa_product_id=product_id,
        message=msg,
    )


@app.post("/reject/{draft_id}")
async def reject_draft(draft_id: str, req: RejectRequest = RejectRequest()):
    store = get_store()
    if not store.configured:
        raise HTTPException(503, "Supabase not configured")
    draft = await store.get_by_id(draft_id)
    if not draft:
        raise HTTPException(404, "Draft not found")
    extra = {}
    if req.reason:
        gl = dict(draft.generated_listing or {})
        gl["reject_reason"] = req.reason
        extra["generated_listing"] = gl
    updated = await store.update_status(draft_id, "rejected", extra)
    return {"id": draft_id, "status": updated.status if updated else "rejected"}


@app.post("/edit/{draft_id}", response_model=DraftListing)
async def edit_draft(draft_id: str, req: EditRequest):
    store = get_store()
    if not store.configured:
        raise HTTPException(503, "Supabase not configured")
    draft = await store.get_by_id(draft_id)
    if not draft:
        raise HTTPException(404, "Draft not found")
    if draft.status != "pending":
        raise HTTPException(400, "Only pending drafts can be edited")

    fields = {}
    if req.title is not None:
        fields["title"] = req.title
    if req.description is not None:
        fields["description"] = req.description
    if req.features is not None:
        fields["features"] = req.features[:5]
    if req.price is not None:
        fields["price"] = req.price
    if req.images is not None:
        fields["images"] = req.images

    if not fields:
        raise HTTPException(400, "No fields to update")

    updated = await store.update_draft(draft_id, fields)
    if not updated:
        raise HTTPException(500, "Update failed")
    return updated
