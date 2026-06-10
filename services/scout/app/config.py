from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path("/opt/sentinel/scout/.env")
if not _ENV_FILE.exists():
    _ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(_ENV_FILE),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    serper_api_key: str = ""
    ollama_host: str = "http://localhost:11434"
    ollama_model: str = "mistral"
    medusa_api_url: str = "http://localhost:9000"
    medusa_api_key: str = ""
    supabase_url: str = ""
    supabase_service_role_key: str = ""
    lister_url: str = "http://localhost:8002"
    log_file: str = "/opt/sentinel/logs/scout.log"
    port: int = 8001
    min_deal_score: float = 7.0
    scan_categories: str = (
        "laptops,desktops,graphics cards,CPUs,monitors,phones,tablets,gaming consoles"
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
