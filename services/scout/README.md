# Sentinel Scout

Live deal-finding AI that scans retail and secondary markets, scores deals with Ollama mistral, and surfaces approval cards in Supabase.

## Run locally

```bash
cd /opt/sentinel/scout
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium
cp .env.example .env   # fill keys
uvicorn app.main:app --host 0.0.0.0 --port 8001
```

## Endpoints

- `POST /search` — search and score deals
- `POST /scan` — full category scan
- `GET /approvals` — pending approval cards
- `POST /approve/{id}` — approve and trigger Lister
- `POST /reject/{id}` — reject with optional reason
- `GET /health` — health check

## Supabase

Run `schema.sql` in the Supabase SQL editor before first use.
