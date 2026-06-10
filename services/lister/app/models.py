from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class ListRequest(BaseModel):
    input: str = Field(..., description="Product name or URL")


class GeneratedListing(BaseModel):
    title: str
    description: str
    features: list[str] = Field(default_factory=list, max_length=5)
    suggested_price: float = 0.0


class DraftListing(BaseModel):
    id: str
    input: str
    source_url: str = ""
    title: str = ""
    description: str = ""
    features: list[str] = Field(default_factory=list)
    images: list[str] = Field(default_factory=list)
    price: float = 0.0
    retailer: str = ""
    raw_extract: dict[str, Any] = Field(default_factory=dict)
    generated_listing: dict[str, Any] = Field(default_factory=dict)
    status: str = "pending"
    medusa_product_id: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class ListResponse(BaseModel):
    draft: DraftListing
    preview: GeneratedListing


class RejectRequest(BaseModel):
    reason: str = ""


class EditRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    features: Optional[list[str]] = None
    price: Optional[float] = None
    images: Optional[list[str]] = None


class ApproveResponse(BaseModel):
    id: str
    status: str
    medusa_product_id: str
    message: str = ""
