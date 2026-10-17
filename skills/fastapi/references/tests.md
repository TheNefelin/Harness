## 13. Tests (con BD real, aislada y segura)

Principios:
- **BD real PostgreSQL dedicada** (`TEST_DATABASE_URL`), no SQLite: los tests prueban lo mismo que prod (tipos, FKs, asyncpg). **Una BD de tests por proyecto, aislada; nunca la compartida.**
- **Aislamiento, no detección**: el fixture **resetea el esquema** de esa BD dedicada (`DROP SCHEMA public CASCADE; CREATE SCHEMA public`) al inicio. Al vivir en una BD propia, el DDL destructivo no puede alcanzar datos ni constraints de otros proyectos. No corras los tests contra un conjunto de tablas dentro de una base compartida: `CASCADE` arrastra los constraints de las tablas ajenas que dependan de las tuyas.
- **Guard de destino (barrera temprana, no la garantía)**: `conftest.py` aborta antes de tocar nada si `TEST_DATABASE_URL` no termina en `_test`, es `postgres`, o su **destino** (host resuelto a IP, puerto, nombre) coincide con `DATABASE_URL`. Es *best-effort* (alias/DNS/proxies pueden eludirlo): la **garantía real** son credenciales **sin permisos de DDL/DROP sobre producción** + la BD dedicada.
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
import socket
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import text
from sqlalchemy.engine import make_url
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

# Guard de destino: barrera temprana contra una BD no aislada. Comprueba el
# DESTINO completo (host resuelto a IP, puerto, nombre), no solo el nombre.
def _resolve_host(host: str) -> set:
  try:
    return {info[4][0] for info in socket.getaddrinfo(host, None)}
  except OSError:
    return {host}


_test = make_url(settings.TEST_DATABASE_URL)
_dev = make_url(settings.DATABASE_URL) if getattr(settings, "DATABASE_URL", None) else None
if not _test.database or not _test.database.endswith("_test") or _test.database == "postgres":
    raise RuntimeError(
        "TEST_DATABASE_URL debe apuntar a una BD de pruebas dedicada "
        f"(nombre terminado en '_test'), no '{_test.database}'."
    )
if _dev and _resolve_host(_test.host or "") & _resolve_host(_dev.host or "") \
        and (_test.port, _test.database) == (_dev.port, _dev.database):
    raise RuntimeError(
        "TEST_DATABASE_URL apunta al MISMO destino que DATABASE_URL (dev/producción); "
        "rechazado para no borrar datos."
    )

engine = create_async_engine(settings.TEST_DATABASE_URL, poolclass=NullPool)
TestingSessionLocal = async_sessionmaker(autocommit=False, autoflush=False, bind=engine, class_=AsyncSession)


# Solo las tablas de ESTE proyecto (mismo prefijo que prod), para limpiar entre
# tests. El aislamiento entre proyectos lo da la BD dedicada, no esta lista.
TEST_TABLES = ["app_wishlist_items", "app_reviews", "app_products",
               "app_categories", "app_user_sessions", "app_users", "app_roles"]


async def _clean_tables(session: AsyncSession):
  """Vacía las tablas del proyecto entre tests (reset de identidades)."""
  await session.execute(
    text(f"TRUNCATE {', '.join(TEST_TABLES)} RESTART IDENTITY CASCADE")
  )
  await session.commit()


@pytest.fixture(scope="module")
async def setup_db():
  # Reset del esquema: seguro SOLO porque la BD es dedicada y el rol no tiene
  # permisos sobre producción. No usar este patrón sobre una BD compartida.
  async with engine.begin() as conn:
    await conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
    await conn.execute(text("CREATE SCHEMA public"))
    await conn.run_sync(Base.metadata.create_all)
  yield
  # Sin teardown destructivo: la BD de tests es desechable y se resetea al inicio.


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

**Flujo de trabajo**: `pytest` corre contra `TEST_DATABASE_URL` (BD dedicada `*_test`, esquema reseteado al inicio); **nunca** toca la BD de desarrollo/producción, y el rol de tests **no debe tener permisos de DDL/DROP** sobre ella. Para repoblar la BD de desarrollo (p. ej. tras un seed manual) usa `repopulate_db.py --force`; el seed debe ser idempotente (FKs por natural keys, no IDs en duro).
