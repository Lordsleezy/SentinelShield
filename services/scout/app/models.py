from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class SearchRequest(BaseModel):
    query: str
    max_results: int = Field(default=10, ge=1, le=50)


class DealResult(BaseModel):
    title: str
    price: float
    market_value: float
    source: str
    url: str
    image: str = ""
    condition: str = "unknown"
    score: Optional[float] = None
    reasoning: Optional[str] = None


class ScoredDeal(DealResult):
    score: float
    reasoning: str


class SearchResponse(BaseModel):
    query: str
    total_found: int
    qualifying: int
    results: list[ScoredDeal]


class ScanResponse(BaseModel):
    categories_scanned: int
    total_deals_found: int
    qualifying_deals: int
    new_approval_cards: int
    details: list[dict[str, Any]]


class ApprovalCard(BaseModel):
    id: str
    title: str
    price: float
    market_value: float
    source: str
    url: str
    image: str
    condition: str
    score: float
    reasoning: str
    status: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class RejectRequest(BaseModel):
    reason: str = ""


class ApproveResponse(BaseModel):
    id: str
    status: str
    lister_triggered: bool
    lister_message: str = ""
