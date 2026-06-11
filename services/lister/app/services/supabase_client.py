import logging
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import uuid4

import httpx

from app.config import get_settings
from app.models import DraftListing, GeneratedListing

logger = logging.getLogger(__name__)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS lister_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    input TEXT NOT NULL,
    source_url TEXT,
    title TEXT,
    description TEXT,
    features JSONB DEFAULT '[]',
    images JSONB DEFAULT '[]',
    price NUMERIC,
    retailer TEXT,
    raw_extract JSONB DEFAULT '{}',
    generated_listing JSONB DEFAULT '{}',
    status TEXT DEFAULT 'pending',
    medusa_product_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_lister_drafts_status ON lister_drafts(status);
"""


class SupabaseStore:
    def __init__(self) -> None:
        s = get_settings()
        self.url = s.supabase_url.rstrip("/")
        self.key = s.supabase_service_role_key
        self.headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }

    @property
    def configured(self) -> bool:
        return bool(self.url and self.key)

    async def ensure_table(self) -> bool:
        if not self.configured:
            logger.warning("Supabase not configured")
            return False
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(
                    f"{self.url}/rest/v1/lister_drafts",
                    headers=self.headers,
                    params={"select": "id", "limit": "1"},
                )
                if resp.status_code == 200:
                    logger.info("lister_drafts table exists")
                    return True
                logger.error("lister_drafts missing — run schema.sql in Supabase")
        except Exception as exc:
            logger.error("Supabase check failed: %s", exc)
        return False

    async def create_draft(
        self,
        user_input: str,
        source_url: str,
        extracted: dict,
        listing: GeneratedListing,
        retailer: str,
    ) -> Optional[DraftListing]:
        if not self.configured:
            return None
        row = {
            "id": str(uuid4()),
            "input": user_input,
            "source_url": source_url,
            "title": listing.title,
            "description": listing.description,
            "features": listing.features,
            "images": extracted.get("images", []),
            "price": listing.suggested_price,
            "retailer": retailer,
            "raw_extract": extracted,
            "generated_listing": listing.model_dump(),
            "status": "pending",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                f"{self.url}/rest/v1/lister_drafts",
                headers=self.headers,
                json=row,
            )
            if resp.status_code >= 400:
                logger.error("Insert failed: %s %s", resp.status_code, resp.text)
                return None
            data = resp.json()
            return _to_draft(data[0] if isinstance(data, list) else data)

    async def get_scout_approval_by_url(self, url: str) -> Optional[dict[str, Any]]:
        if not self.configured or not url:
            return None
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{self.url}/rest/v1/scout_approvals",
                headers=self.headers,
                params={"url": f"eq.{url}", "limit": "1"},
            )
            if resp.status_code >= 400:
                logger.warning("Scout approval lookup failed: %s %s", resp.status_code, resp.text)
                return None
            rows = resp.json()
            return rows[0] if rows else None

    async def list_pending(self) -> list[DraftListing]:
        if not self.configured:
            return []
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{self.url}/rest/v1/lister_drafts",
                headers=self.headers,
                params={"status": "eq.pending", "order": "created_at.desc"},
            )
            resp.raise_for_status()
            return [_to_draft(r) for r in resp.json()]

    async def get_by_id(self, draft_id: str) -> Optional[DraftListing]:
        if not self.configured:
            return None
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{self.url}/rest/v1/lister_drafts",
                headers=self.headers,
                params={"id": f"eq.{draft_id}", "limit": "1"},
            )
            resp.raise_for_status()
            rows = resp.json()
            return _to_draft(rows[0]) if rows else None

    async def update_draft(self, draft_id: str, fields: dict[str, Any]) -> Optional[DraftListing]:
        if not self.configured:
            return None
        fields["updated_at"] = datetime.now(timezone.utc).isoformat()
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.patch(
                f"{self.url}/rest/v1/lister_drafts",
                headers=self.headers,
                params={"id": f"eq.{draft_id}"},
                json=fields,
            )
            if resp.status_code >= 400:
                return None
            data = resp.json()
            return _to_draft(data[0] if isinstance(data, list) else data)

    async def update_status(
        self, draft_id: str, status: str, extra: dict | None = None
    ) -> Optional[DraftListing]:
        payload = {"status": status}
        if extra:
            payload.update(extra)
        return await self.update_draft(draft_id, payload)


def _to_draft(row: dict) -> DraftListing:
    features = row.get("features") or []
    if isinstance(features, str):
        import json
        features = json.loads(features)
    images = row.get("images") or []
    if isinstance(images, str):
        import json
        images = json.loads(images)
    return DraftListing(
        id=str(row["id"]),
        input=row.get("input", ""),
        source_url=row.get("source_url", ""),
        title=row.get("title", ""),
        description=row.get("description", ""),
        features=features if isinstance(features, list) else [],
        images=images if isinstance(images, list) else [],
        price=float(row.get("price") or 0),
        retailer=row.get("retailer", ""),
        raw_extract=row.get("raw_extract") or {},
        generated_listing=row.get("generated_listing") or {},
        status=row.get("status", "pending"),
        medusa_product_id=row.get("medusa_product_id"),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    )


_store: Optional[SupabaseStore] = None


def get_store() -> SupabaseStore:
    global _store
    if _store is None:
        _store = SupabaseStore()
    return _store
