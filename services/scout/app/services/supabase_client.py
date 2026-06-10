import logging
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import uuid4

import httpx

from app.config import get_settings
from app.models import ApprovalCard, ScoredDeal

logger = logging.getLogger(__name__)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS scout_approvals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    price NUMERIC,
    market_value NUMERIC,
    source TEXT,
    url TEXT,
    image TEXT,
    condition TEXT,
    score NUMERIC,
    reasoning TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scout_approvals_status ON scout_approvals(status);
CREATE INDEX IF NOT EXISTS idx_scout_approvals_url ON scout_approvals(url);
"""


class SupabaseStore:
    def __init__(self) -> None:
        settings = get_settings()
        self.url = settings.supabase_url.rstrip("/")
        self.key = settings.supabase_service_role_key
        self.headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }
        self._ready = False

    @property
    def configured(self) -> bool:
        return bool(self.url and self.key)

    async def ensure_table(self) -> bool:
        if not self.configured:
            logger.warning("Supabase not configured — set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")
            return False
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(
                    f"{self.url}/rest/v1/scout_approvals",
                    headers=self.headers,
                    params={"select": "id", "limit": "1"},
                )
                if resp.status_code == 200:
                    self._ready = True
                    logger.info("scout_approvals table exists")
                    return True
                if resp.status_code == 404:
                    logger.error(
                        "scout_approvals table not found. Run schema.sql in Supabase SQL editor:\n%s",
                        SCHEMA_SQL,
                    )
        except Exception as exc:
            logger.error("Supabase check failed: %s", exc)
        return False

    async def create_approval(self, deal: ScoredDeal) -> Optional[ApprovalCard]:
        if not self.configured:
            return None
        row = {
            "id": str(uuid4()),
            "title": deal.title,
            "price": deal.price,
            "market_value": deal.market_value,
            "source": deal.source,
            "url": deal.url,
            "image": deal.image,
            "condition": deal.condition,
            "score": deal.score,
            "reasoning": deal.reasoning,
            "status": "pending",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                f"{self.url}/rest/v1/scout_approvals",
                headers=self.headers,
                json=row,
            )
            if resp.status_code >= 400:
                logger.error("Supabase insert failed: %s %s", resp.status_code, resp.text)
                return None
            data = resp.json()
            return _row_to_card(data[0] if isinstance(data, list) else data)

    async def list_pending(self) -> list[ApprovalCard]:
        if not self.configured:
            return []
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{self.url}/rest/v1/scout_approvals",
                headers=self.headers,
                params={
                    "status": "eq.pending",
                    "order": "created_at.desc",
                },
            )
            resp.raise_for_status()
            return [_row_to_card(r) for r in resp.json()]

    async def get_by_id(self, approval_id: str) -> Optional[ApprovalCard]:
        if not self.configured:
            return None
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{self.url}/rest/v1/scout_approvals",
                headers=self.headers,
                params={"id": f"eq.{approval_id}", "limit": "1"},
            )
            resp.raise_for_status()
            rows = resp.json()
            return _row_to_card(rows[0]) if rows else None

    async def update_status(self, approval_id: str, status: str, reason: str = "") -> Optional[ApprovalCard]:
        if not self.configured:
            return None
        payload: dict[str, Any] = {
            "status": status,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if reason:
            payload["reasoning"] = reason
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.patch(
                f"{self.url}/rest/v1/scout_approvals",
                headers=self.headers,
                params={"id": f"eq.{approval_id}"},
                json=payload,
            )
            if resp.status_code >= 400:
                logger.error("Supabase update failed: %s", resp.text)
                return None
            data = resp.json()
            return _row_to_card(data[0] if isinstance(data, list) else data)

    async def known_urls(self) -> set[str]:
        if not self.configured:
            return set()
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{self.url}/rest/v1/scout_approvals",
                headers=self.headers,
                params={"select": "url"},
            )
            if resp.status_code >= 400:
                return set()
            return {r["url"] for r in resp.json() if r.get("url")}


def _row_to_card(row: dict) -> ApprovalCard:
    return ApprovalCard(
        id=str(row["id"]),
        title=row.get("title", ""),
        price=float(row.get("price") or 0),
        market_value=float(row.get("market_value") or 0),
        source=row.get("source", ""),
        url=row.get("url", ""),
        image=row.get("image", ""),
        condition=row.get("condition", ""),
        score=float(row.get("score") or 0),
        reasoning=row.get("reasoning", ""),
        status=row.get("status", "pending"),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    )


_store: Optional[SupabaseStore] = None


def get_store() -> SupabaseStore:
    global _store
    if _store is None:
        _store = SupabaseStore()
    return _store
