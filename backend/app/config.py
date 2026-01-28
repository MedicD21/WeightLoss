"""Application configuration."""
from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # App
    app_name: str = "Logged Fitness Tracker API"
    app_version: str = "1.0.0"
    debug: bool = False
    db_auto_init: bool = False

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # Database
    database_url: str = "postgresql+asyncpg://logged:logged_secret@localhost:5432/logged_db"
    database_echo: bool = False
    auth_database_url: Optional[str] = None

    # Redis (for caching and rate limiting)
    redis_url: str = "redis://localhost:6379/0"

    # JWT Authentication
    jwt_secret_key: str = "your-super-secret-key-change-in-production"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7

    # Magic Link
    magic_link_expire_minutes: int = 15
    magic_link_base_url: str = "logged://auth/verify"

    # Email (for magic links)
    smtp_host: Optional[str] = None
    smtp_port: int = 587
    smtp_user: Optional[str] = None
    smtp_password: Optional[str] = None
    smtp_from_email: str = "noreply@logged.app"

    # OpenAI API
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-4-turbo-preview"
    openai_vision_model: str = "gpt-4-vision-preview"
    openai_base_url: Optional[str] = None  # For OpenAI-compatible providers

    # Anthropic API
    anthropic_api_key: Optional[str] = None
    claude_model: str = "claude-sonnet-4-20250514"
    claude_vision_model: str = "claude-sonnet-4-20250514"
    claude_max_tokens: int = 4096
    ai_provider: str = "anthropic"  # "anthropic" (default) or "openai"

    # Open Food Facts
    off_api_url: str = "https://world.openfoodfacts.org/api/v2"
    off_user_agent: str = "Logged Fitness Tracker/1.0 (contact@logged.app)"

    # Apple Sign In
    apple_client_id: Optional[str] = None
    apple_team_id: Optional[str] = None
    apple_key_id: Optional[str] = None
    apple_private_key: Optional[str] = None

    # Rate Limiting
    rate_limit_requests_per_minute: int = 60

    # CORS
    cors_origins: list[str] = ["*"]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
    )


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
