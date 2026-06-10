-- Run once in Supabase SQL Editor (Dashboard → SQL → New query)
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

-- Enable RLS optional; service role bypasses RLS
ALTER TABLE scout_approvals ENABLE ROW LEVEL SECURITY;
