## 13. Tests (con BD real, aislada y segura)

Principios:
- **BD real PostgreSQL** (`TEST_DATABASE_URL`), no SQLite: los tests prueban lo mismo que prod (tipos, FKs, asyncpg).
- **Nunca dropear toda la BD compartida**: el fixture dropea **solo las tablas de este proyecto** (por prefijo de tabla) al inicio y al teardown.
- **Guard de destino**: `conftest.py` aborta antes de tocar nada si `TEST_DATABASE_URL` no es una BD dedicada (nombre `*_test`) o coincide con la de desarrollo/producción.
- `conftest.py` centraliza: engine, sesión, override de `get_db` y `verify_api_key`, y siembra los datos mínimos (roles y un usuario admin).
- Un test = 1 caso (éxito + cada error). Fórmula por recurso: create ✓, duplicate ✗, list empty, list, filter, get_by_id, get_by_id 404, update, update 404, update duplicate, delete, delete 404, pagination.
- **Tests live aislados**: los que tocan servicios externos reales (enviar email a Brevo, cobrar, subir a Cloudinary) van en archivos `test_*_live.py` marcados `@pytest.mark.live` y **excluidos por defecto** (`addopts = -m "not live"` en `pytest.ini`). Solo corren a demanda con `pytest -m live`. Esto evita que la suite común dispare llamadas pagadas/irreversibles. Condicional extra si requieren credencial: `@pytest.mark.skipif(not settings.TEST_BREVO_EMAIL)`.

```ini
# pytest.ini
[pytest]
pythonpath = .
asyncio_mode = auto
addopts = -m "not live"

[markers]
live: tests que tocan servicios externos reales (envio de email, pagos); se corren a demanda con `pytest -m live`
```

```python
# tests/test_contact_live.py
import pytest
from src.core.config import settings
from src.api.contact import brevo

pytestmark = pytest.mark.live


@pytest.mark.skipif(not settings.TEST_BREVO_EMAIL, reason="TEST_BREVO_EMAIL no configurado")
async def test_send_contact_email_live():
  message_id = await brevo.send_contact_email(to=settings.TEST_BREVO_EMAIL, ...)
  assert message_id
```

### `tests/conftest.py`

```python
from uuid import uuid4, UUID
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import NullPool

from src.core.database import Base, get_db
from src.core.config import settings
from src.core.dependencies import verify_api_key
from src.core.limiter import limiter
from src.core.security import create_access_token
from src.main import app

ADMIN_USER_ID = UUID("00000000-0000-0000-0000-000000000001")
ADMIN_TOKEN = create_access_token(ADMIN_USER_ID, "admin")

# Guard de destino: nunca ejecutar DDL destructivo contra una BD no aislada.
_db_name = settings.TEST_DATABASE_URL.rsplit("/", 1)[-1].split("?")[0]
_dev_name = (settings.DATABASE_URL.rsplit("/", 1)[-1].split("?")[0]
             if hasattr(settings, "DATABASE_URL") else None)
if not _db_name.endswith("_test") or _db_name == "postgres" or _db_name == _dev_name:
    raise RuntimeError(
        "TEST_DATABASE_URL debe apuntar a una BD de pruebas dedicada "
        "(nombre terminado en '_test'); destino rechazado para no borrar datos."
    )

engine = create_async_engine(settings.TEST_DATABASE_URL, poolclass=NullPool)
TestingSessionLocal = async_sessionmaker(autocommit=False, autoflush=False, bind=engine, class_=AsyncSession)


async def _clean_tables(session: AsyncSession):
  """Delete all data from test-relevant tables in FK-safe order."""  # enlistar tablas del proyecto
  ...


# Solo las tablas de ESTE proyecto (mismo prefijo que prod). NUNCA dropear
# todas las de la BD compartida.
TEST_TABLES = ["app_wishlist_items", "app_reviews", "app_products",
               "app_categories", "app_user_sessions", "app_users", "app_roles"]


async def _drop_test_tables(conn):
  for table in TEST_TABLES:
    await conn.execute(text(f"DROP TABLE IF EXISTS {table} CASCADE"))


@pytest.fixture(scope="module")
async def setup_db():
  async with engine.begin() as conn:
    await _drop_test_tables(conn)
    await conn.run_sync(Base.metadata.create_all)
  yield
  # Solo dropear las tablas de este proyecto (no tocar las de otros que
  # comparten la BD de testing).
  async with engine.begin() as conn:
    await _drop_test_tables(conn)
  # OPCIONAL: por defecto NO usar drop_all sobre una BD compartida.


@pytest.fixture
async def db(setup_db):
  async with TestingSessionLocal() as session:
    await _clean_tables(session)
    # Seed mínimo del proyecto: roles y usuario admin (con IDs fijos para los
    # tokens de prueba).
    session.add_all([Role(id=1, name="user"), Role(id=2, name="admin")])
    session.add(User(id=ADMIN_USER_ID, email="admin@test.com", role_id=2))
    await session.flush()
    yield session


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
  limiter.reset()
  yield


@pytest.fixture
async def client(db):
  async def override_get_db():
    yield db

  async def override_verify_api_key():
    return True

  app.dependency_overrides[get_db] = override_get_db
  app.dependency_overrides[verify_api_key] = override_verify_api_key
  async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test",
                         headers={"Authorization": f"Bearer {ADMIN_TOKEN}"}) as ac:
    yield ac
  app.dependency_overrides.clear()
```

### Ejemplo de test (`tests/test_products.py`)

```python
async def test_create_product(client, db):
  response = await client.post("/api/products/", json={
    "category_id": 1, "name": "Widget", "slug": "widget", "price": 1000,
  })
  assert response.status_code == 201
  assert response.json()["name"] == "Widget"


async def test_create_product_duplicate_name(client, db):
  await client.post("/api/products/", json={"category_id": 1, "name": "Widget", "slug": "widget", "price": 1000})
  response = await client.post("/api/products/", json={"category_id": 1, "name": "Widget", "slug": "other", "price": 500})
  assert response.status_code == 400
  assert "already exists" in response.json()["detail"]
```

**Flujo de trabajo**: `pytest` corre contra `TEST_DATABASE_URL` (BD dedicada `*_test`); **nunca** toca la BD de desarrollo/producción. Para repoblar la BD de desarrollo (p. ej. tras un seed manual) usa `repopulate_db.py --force`; el seed debe ser idempotente (FKs por natural keys, no IDs en duro).
