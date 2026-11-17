"""Settings for the monitoring API, read from environment variables (or a .env file)."""

import os
from urllib.parse import quote_plus

import certifi


def database_settings():
    """Return (url, engine_options) for SQLAlchemy.

    In Azure, DB_HOST/DB_NAME/DB_USER/DB_PASSWORD point at the MySQL Flexible Server.
    TLS is required by the server, so the connection verifies its certificate.
    Locally, without DB_HOST, a SQLite file is used (DATABASE_URL can override it).
    """
    host = os.getenv("DB_HOST")
    if not host:
        return os.getenv("DATABASE_URL", "sqlite:///monitoring.db"), {}

    user = quote_plus(os.getenv("DB_USER", "khadmin"))
    password = quote_plus(os.getenv("DB_PASSWORD", ""))
    name = os.getenv("DB_NAME", "monitoring")
    port = os.getenv("DB_PORT", "3306")
    url = f"mysql+pymysql://{user}:{password}@{host}:{port}/{name}?charset=utf8mb4"
    options = {
        "connect_args": {"ssl": {"ca": certifi.where()}},
        "pool_pre_ping": True,   # reconnect after the server closed an idle connection
        "pool_recycle": 280,
    }
    return url, options


class Config:
    def __init__(self):
        self.SQLALCHEMY_DATABASE_URI, self.SQLALCHEMY_ENGINE_OPTIONS = database_settings()
        self.API_KEY = os.getenv("API_KEY", "")
        self.MAX_BATCH = int(os.getenv("MAX_BATCH", "500"))
        self.LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
