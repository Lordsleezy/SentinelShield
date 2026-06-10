-- Run in Supabase SQL Editor
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
