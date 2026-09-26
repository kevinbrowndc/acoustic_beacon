from typing import Literal

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AB_", env_file=".env", extra="forbid", hide_input_in_errors=True)
    environment: Literal["development", "test", "production"] = "development"
    database_url: SecretStr = SecretStr("sqlite:///./beacon.db")
    cors_origins: list[str] = []
    provision_test_beacon: bool = False

    @field_validator("database_url", mode="before")
    @classmethod
    def render_postgres_url(cls, value):
        raw = value.get_secret_value() if isinstance(value, SecretStr) else str(value)
        for prefix in ("postgres://", "postgresql://"):
            if raw.startswith(prefix):
                return "postgresql+psycopg://" + raw[len(prefix):]
        return value

    @field_validator("cors_origins")
    @classmethod
    def explicit_origins(cls, values):
        from urllib.parse import urlsplit
        for value in values:
            origin = urlsplit(value)
            if origin.scheme != "https" or not origin.netloc or origin.username or origin.password or origin.path or origin.query or origin.fragment:
                raise ValueError("CORS origins must be explicit HTTPS origins without paths")
        return values

    @model_validator(mode="after")
    def validate_database(self):
        try:
            driver = make_url(self.database_url.get_secret_value()).drivername
        except Exception:
            raise ValueError("Invalid database URL") from None
        if driver not in {"sqlite", "postgresql+psycopg"}:
            raise ValueError("Use sqlite or postgresql+psycopg")
        if self.environment == "production" and driver != "postgresql+psycopg":
            raise ValueError("Production requires PostgreSQL")
        return self
