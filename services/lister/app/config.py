from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
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
    log_file: str = "/opt/sentinel/logs/lister.log"
    port: int = 8002
    cors_origins: str = "http://localhost:3000,http://127.0.0.1:3000,http://192.168.0.117:3000,https://dashboard.sentinelprime.org"


@lru_cache
def get_settings() -> Settings:
    return Settings()
