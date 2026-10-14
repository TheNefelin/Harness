# Configuración y logging

## `src/core/config.py` (pydantic-settings)

Todo lo externo es **opcional** (el proyecto decide qué integra). Las variables `TEST_*` son `None` por defecto y solo las leen las pruebas; se declaran igual en el `Settings` porque Pydantic ignora variables `.env` que no estén declaradas aquí.

```python
import json
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
  DEBUG: bool = False

  DATABASE_URL: str
  TEST_DATABASE_URL: str | None = None   # solo para tests (BD real aislada)

  CORS_ORIGINS: str  # JSON string: ["http://localhost:3000"]
  SECRET_KEY: str
  API_KEY: str

  # Externos opcionales según el proyecto:
  GOOGLE_CLIENT_ID: str | None = None
  CLOUDINARY_CLOUD_NAME: str | None = None
  CLOUDINARY_API_KEY: str | None = None
  CLOUDINARY_API_SECRET: str | None = None
  BREVO_API_KEY: str | None = None
  BREVO_FROM_EMAIL: str | None = None
  BREVO_FROM_NAME: str | None = None
  TEST_BREVO_EMAIL: str | None = None   # solo para tests live

  @property
  def cors_origins_list(self) -> list[str]:
    return json.loads(self.CORS_ORIGINS)

  model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()
```

Nota: si una integración es obligatoria, mueve esa variable a `str` sin default — arrancará con error claro si falta. Ejemplo real: `DATABASE_URL`, `SECRET_KEY`, `API_KEY` son requeridas; Cloudinary y Brevo son opcionales.

## `src/core/database.py`

```python
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import declarative_base

from src.core.config import settings

engine = create_async_engine(settings.DATABASE_URL, echo=settings.DEBUG, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(autocommit=False, autoflush=False, bind=engine, class_=AsyncSession)
Base = declarative_base()


async def get_db():
  async with AsyncSessionLocal() as session:
    yield session
```

## `src/core/logger.py` (JSON + request_id por petición)

```python
import json, logging, sys
from contextvars import ContextVar
from datetime import datetime, timezone

_request_id: ContextVar[str] = ContextVar("request_id", default="")


def set_request_id(value: str) -> None:
  _request_id.set(value)


def get_request_id() -> str:
  return _request_id.get()


class JsonFormatter(logging.Formatter):
  def format(self, record: logging.LogRecord) -> str:
    entry = {"timestamp": datetime.now(tz=timezone.utc).isoformat(), "level": record.levelname,
             "logger": record.name, "message": record.getMessage(), "request_id": get_request_id()}
    if hasattr(record, "props"):
      entry.update(record.props)
    return json.dumps(entry, ensure_ascii=False)


def setup_logger() -> logging.Logger:
  logger = logging.getLogger("api")
  logger.setLevel(logging.INFO)
  handler = logging.StreamHandler(sys.stdout)
  handler.setFormatter(JsonFormatter())
  logger.addHandler(handler)
  return logger


logger = setup_logger()
```

```python
# main.py — middleware que setea el request_id y loguea cada request
@app.middleware("http")
async def log_requests(request: Request, call_next):
  request_id = str(uuid.uuid4())
  set_request_id(request_id)
  start = time.time()
  response = await call_next(request)
  logger.info("%s %s", request.method, request.url.path, extra={
    "props": {"method": request.method, "path": request.url.path,
              "status_code": response.status_code,
              "duration_ms": round((time.time() - start) * 1000, 2)}})
  return response
```
