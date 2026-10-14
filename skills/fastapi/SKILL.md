---
name: fastapi
description: Patrón senior para APIs REST en Python con FastAPI, SQLAlchemy 2.0 async y PostgreSQL. Usar cuando se cree, modifique o revise una API FastAPI: endpoints, modelos, servicios, auth, uploads, email o testing.
---

# SKILL: API FastAPI en Python — Patrón Senior (transversal)

Guía de referencia para construir APIs REST con **FastAPI + SQLAlchemy 2.0 (async) + PostgreSQL**, siguiendo una arquitectura y convenciones senior validadas en producción. Es **transversal**: los ejemplos son genéricos (CRUD, catálogos, auth, uploads, email) y aplican a cualquier dominio — e-commerce, SaaS, contenido, fintech, lo que sea.

Este archivo es un **skill**: se lee para replicar el patrón en cualquier API nueva. No es una receta dogmática, es la lista de decisiones que convierten un CRUD simple en un backend mantenible.

**Servicios externos (todos opcionales según el proyecto, y por eso se configuran como tal):**
- **Auth**: Google OAuth (`api/auth/google_service.py`) + JWT + refresh rotation — reemplazable por cualquier proveedor OAuth.
- **Imágenes**: Cloudinary (`core/cloudinary.py`) — el patrón de almacenamiento es el mismo para cualquier servicio (S3, etcétera).
- **Email transaccional**: Brevo (`api/contact/brevo.py`) — REST API `/v3/smtp/email` con httpx async; el patrón aplica a cualquier proveedor.

**Referencias** (se leen bajo demanda, rutas relativas a esta skill): `references/auth.md`, `references/uploads.md`, `references/email.md`, `references/rate-limiting.md`, `references/tests.md`.

---

## 1. ¿Por qué este patrón es SENIOR?

Porque resuelve los problemas que matan a las APIs FastAPI cuando crecen, con decisiones **justificadas**, no por moda:

| Decisión | Problema que resuelve |
|----------|----------------------|
| **Feature-based** (`api/{feature}/routes|service|repository`) | El código crece por dominio, no por capa. Agregar una feature = crear 1 carpeta, sin tocar archivos ajenos |
| **Route→Service→Repository** (separación estricta) | Cada capa tiene una única responsabilidad; los errores se disparan donde se descubre el dato, no donde se usa |
| **Cross-feature solo service→service** (nunca repository de otra feature) | Las features se acoplan por su API pública (lógica), no por su implementación (datos): cambiar una tabla no rompe a las demás |
| **DTOs en `schemas/dtos.py`** + `model_validate` | El contrato HTTP se desacopla del modelo ORM: cambiás la DB sin romper el frontend |
| **Paginación unificada por DTO** (`PaginationRequest`/`PaginationResponse`) | Todos los listados responden igual: `{page, limit, total, items}`. El frontend tiene 1 solo patrón de consumo |
| **`AppError`/subclases → RFC 9457 (ProblemDetails)** | Errores consistentes (`{type,title,status,detail}`), sin depender de cómo cada ruta arma el `JSONResponse` |
| **JWT identifica usuario + rol REAL leído de la BD en cada request** | El token solo prueba QUÉN es; el permiso se consulta en la BD (ver `get_current_user`) — un cambio de rol o baja de usuario se refleja al instante, sin esperar la expiración del token |
| **`ApiKey` global + JWT por usuario** | Separa "quién puede llamar a la API" (BFF/origen) de "quién es el usuario" (autorización) |
| **Async en toda la pila** (`asyncpg`, `AsyncSession`) | Sin bloqueo en I/O: una API async real, no async de adorno |
| **Rate limiting por identidad** (JWT → `user:{id}`, si no → IP) | Protección de fuerza bruta que no castiga a todos por un solo abusador: si el request trae token, el límite es por usuario |
| **Logging JSON con `request_id`** | Trazabilidad: cada log de una petición comparte el mismo ID |
| **Cliente externo según uso** (Cloudinary en `core/` vs Google/Brevo en el feature) | Si lo usa ≥2 features va en `core/`; si lo usa 1 feature va encapsulado dentro de esa feature (sin acoplar `core/` con dominios) |
| **Tests con BD real aislada** | Los tests corren contra la misma tecnología de prod (PostgreSQL), con fixtures que dropean **solo sus tablas** |
| **Tests live aislados por marker** (`@pytest.mark.live`) | Los tests que tocan servicios externos reales (enviar mail, cobrar) no corren en CI: se excluyen por defecto y se ejecutan a demanda |
| **Errores de negocio ≠ errores HTTP** | El service lanza `NotFoundError("Product")` (semántico) y el framework lo traduce a 404. Nunca `HTTPException` en rutas |
| **Errores de proveedor mapeados** | Un fallo de un servicio externo se traduce según su status (`401/403`→config, `429`→rate limit, resto→`502`), nunca un `502` genérico que trague el detalle real |

---

## 2. Stack

| Capa | Tecnología |
|------|-----------|
| Runtime | Python 3.12+ |
| Framework | FastAPI (última estable) + Uvicorn |
| ORM | SQLAlchemy 2.0 (estilo `Mapped`/`mapped_column`) + `asyncpg` |
| Validación | Pydantic v2 (`from_attributes=True`) |
| Auth | Google OAuth (opcional), `python-jose` (JWT HS256), refresh token rotation |
| Errores | `fastapi-problem` (RFC 9457) |
| Rate limit | `slowapi` |
| Logging | Logging estándar + formatter JSON + `ContextVar` para `request_id` |
| Imágenes | Cloudinary (o cualquier servicio: el patrón es el mismo) |
| Email transaccional | Brevo REST API (`/v3/smtp/email`) con `httpx` async (el patrón aplica a cualquier proveedor) |
| Tests | `pytest` + `pytest-asyncio` + `httpx` |

---

## 3. Estructura de carpetas (plantilla)

```
project/
├── .env                     # secretos (nunca commitear)
├── .env_demo                # plantilla sin valores reales
├── pytest.ini               # pythonpath = . | asyncio_mode = auto | addopts = -m "not live"
├── requirements.txt         # versiones fijas (pip freeze)
├── run.py                   # uvicorn src.main:app --reload
├── src/
│   ├── main.py              # app FastAPI, CORS, routers, exception handlers
│   ├── core/                # transversal: config, database, security, exceptions, logger, limiter, dependencies
│   ├── models/
│   │   └── models.py        # UN SOLO archivo de modelos (evita imports circulares)
│   ├── schemas/
│   │   └── dtos.py          # TODOS los DTOs compartidos (petición/respuesta/paginación)
│   └── api/
│       ├── auth/            # OAuth + JWT + refresh (transversal, siempre presente)
│       │   ├── routes.py           #   endpoints
│       │   ├── schemas.py          #   DTOs específicos del auth
│       │   ├── service.py          #   lógica de negocio
│       │   ├── google_service.py   #   cliente del proveedor OAuth (httpx)
│       │   └── session_repository.py
│       ├── users/           # feature: usuarios (siempre presente; la consume security)
│       ├── roles/           # feature: catálogo de roles/aprobaciones (sin routes, solo repository+service)
│       ├── products/        # feature CRUD de ejemplo
│       │   ├── routes.py        #   endpoints
│       │   ├── service.py       #   reglas de negocio
│       │   └── repository.py    #   solo queries SQLAlchemy
│       ├── categories/      # feature con relación FK a products
│       ├── contact/         # (opcional) feature SIN BD: envía email (cliente externo encapsulado aquí)
│       │   ├── routes.py       #   POST /contact (verify_api_key + require_user + rate limit)
│       │   ├── service.py      #   orquesta: reusa users_service + brevo
│       │   ├── schemas.py      #   DTOs locales del feature (nunca contaminan dtos.py)
│       │   └── brevo.py        #   cliente del proveedor de email (httpx async)
│       └── user_favorites/  # (opcional) feature de lectura combinada del usuario (agrega de varias tablas)
└── tests/
    ├── conftest.py          # fixtures: DB real + TestClient + cleanup
    ├── test_auth.py
    ├── test_products.py
    └── test_contact_live.py # @pytest.mark.live (NO corre en CI, usa TEST_BREVO_EMAIL si aplica)
```

**Regla**: un feature CRUD simple = 3 archivos (`routes.py`, `service.py`, `repository.py`). Si necesita DTOs propios o lógica extra (p. ej. upload), agrega archivos dentro de la misma carpeta. **Nunca** crees un `crud.py` global ni mezcles queries de features distintas.

**Regla de cliente externo por uso**: si un cliente externo lo usa **1 solo feature**, va encapsulado dentro de esa feature (p. ej. `contact/brevo.py`, `auth/google_service.py`). Si lo usan **≥2 features**, sube a `core/` (p. ej. `core/cloudinary.py`). Esto evita acoplar `core/` con dominios específicos.

---

## 4. Convenciones de capas

### 4.1 Route (decide HTTP)
- Solo declara `APIRouter(prefix, tags, dependencies=[Depends(verify_api_key)])`, endpoints y delega al service.
- **Nunca** hace queries, **nunca** arma `JSONResponse` de error, **nunca** valida reglas de negocio.
- `status_code` explícito por endpoint (`HTTP_200_OK/201/204`).
- Endpoints de escritura agregan `_: dict = Depends(require_admin)` (o `require_user` para endpoints de usuario autenticado).
- Paginación se inyecta con `params: Annotated[PaginationRequest, Depends()]`. **NO** usar `Annotated[Model, Query()]` (en FastAPI reciente no se combina con otros query params y rompe con 422).

```python
# src/api/products/routes.py
from typing import Annotated
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.status import HTTP_200_OK, HTTP_201_CREATED, HTTP_204_NO_CONTENT

from src.core.dependencies import verify_api_key, require_admin
from src.core.database import get_db
from src.schemas import dtos
from . import service

router = APIRouter(prefix="/products", tags=["products"], dependencies=[Depends(verify_api_key)])


@router.get("/", response_model=dtos.PaginationResponse[dtos.ProductResponse], status_code=HTTP_200_OK,
            summary="List products", description="Paginated list, optionally filtered by category_id.")
async def get_products(
  params: Annotated[dtos.PaginationRequest, Depends()],
  category_id: int | None = None,
  db: AsyncSession = Depends(get_db),
):
  return await service.get_all(db, params.page, params.limit, category_id, params.search)


@router.get("/{id}", response_model=dtos.ProductResponse, status_code=HTTP_200_OK,
            summary="Get product by ID", description="Returns a product. 404 if not found.")
async def get_product(id: int, db: AsyncSession = Depends(get_db)):
  return await service.get_by_id(db, id)


@router.post("/", response_model=dtos.ProductResponse, status_code=HTTP_201_CREATED,
             summary="Create product")
async def create_product(data: dtos.ProductRequest, db: AsyncSession = Depends(get_db), _: dict = Depends(require_admin)):
  return await service.create(db, data)


@router.put("/{id}", response_model=dtos.ProductResponse, status_code=HTTP_200_OK,
            summary="Update product")
async def update_product(id: int, data: dtos.ProductRequest, db: AsyncSession = Depends(get_db), _: dict = Depends(require_admin)):
  return await service.update(db, id, data)


@router.delete("/{id}", status_code=HTTP_204_NO_CONTENT, summary="Delete product")
async def delete_product(id: int, db: AsyncSession = Depends(get_db), _: dict = Depends(require_admin)):
  await service.delete(db, id)
```

### 4.2 Service (orquesta y aplica reglas de negocio)
- Llama al repository, valida, lanza errores de negocio, mapea a DTOs con `model_validate`.
- **El service decide el error**, el repository solo devuelve datos (`None` si no existe).
- Los `await db.commit()` viven en el repository (capa de datos), nunca en el service. Si una operación necesita varios cambios atómicos, el repository expone un único `delete_by_*`/`remove_*` que los ejecuta y commitea juntos.
- Helpers de validación de FK se exponen para otros features: `ensure_product_exists(db, id)`.
- **Regla cross-feature**: si una feature necesita datos de otra, se importa **su service** (`from src.api.categories import service as categories_service` → `categories_service.exists_by_id(...)`), nunca su repository directamente.
- **Regla de capa de datos**: el service **NUNCA importa `src.models.models`** (entidades ORM). Solo el repository toca entidades. El service tipa y retorna únicamente DTOs (`dtos.*`); si necesita la entidad de su propia feature, el repository se la devuelve y el service la mapea. Si necesita datos de otra feature, usa su service (que devuelve DTOs).
- **Cross-feature con entidades**: jamás se pasan entidades ORM entre services. Se comparten **DTOs o value-objects** (`dataclass` de `core`/`schemas`, p. ej. `src.core.email.EmailData`): el caller mapea su propia entidad al value-object y el receptor solo conoce el contrato de datos. Queries de validación de existencia/FK → métodos del repository propio (`edition_exists`, `copy_status_exists`), nunca `db.get(models.X, ...)` en el service.

```python
# src/api/products/service.py
from sqlalchemy.ext.asyncio import AsyncSession

from src.schemas import dtos
from src.core.exceptions import DuplicateNameError, NotFoundError
from . import repository


async def ensure_product_exists(db: AsyncSession, product_id: int) -> None:
  if not await repository.exists_by_id(db, product_id):
    raise NotFoundError("Product")


async def get_all(db: AsyncSession, page: int = 1, limit: int = 20, category_id: int | None = None, search: str | None = None) -> dtos.PaginationResponse[dtos.ProductResponse]:
  total = await repository.count(db, category_id, search)
  items = [dtos.ProductResponse.model_validate(e) for e in await repository.get_all(db, page, limit, category_id, search)]
  return dtos.PaginationResponse(page=page, limit=limit, total=total, items=items)


async def get_by_id(db: AsyncSession, id: int) -> dtos.ProductResponse:
  entity = await repository.get_by_id(db, id)
  if not entity:
    raise NotFoundError("Product")
  return dtos.ProductResponse.model_validate(entity)


async def create(db: AsyncSession, data: dtos.ProductRequest) -> dtos.ProductResponse:
  if await repository.exists_by_name(db, data.name):
    raise DuplicateNameError(data.name)
  return dtos.ProductResponse.model_validate(await repository.create(db, data.model_dump()))


async def update(db: AsyncSession, id: int, data: dtos.ProductRequest) -> dtos.ProductResponse:
  current = await repository.get_by_id(db, id)
  if not current:
    raise NotFoundError("Product")
  if data.name != current.name and await repository.exists_by_name(db, data.name):
    raise DuplicateNameError(data.name)
  return dtos.ProductResponse.model_validate(await repository.update(db, current, data.model_dump()))


async def delete(db: AsyncSession, id: int) -> None:
  entity = await repository.get_by_id(db, id)
  if not entity:
    raise NotFoundError("Product")
  await repository.delete(db, entity)
```

### 4.3 Repository (solo queries SQLAlchemy)
- Una función por operación: `count`, `get_all`, `get_by_id`, `exists_by_name`, `exists_by_id`, `create`, `update`, `delete`.
- `create`/`update` reciben `dict` (de `data.model_dump()`) y devuelven el modelo refrescado.
- Búsqueda con `ilike` (se omite si `None`/vacío).
- Filtros específicos (p. ej. `category_id`) van como parámetros, **no** dentro del DTO de paginación.
- `commit()` + `refresh()` aquí, no en el service.
- **Es la única capa que importa `src.models.models`**: construye entidades (`models.X(**data)`), ejecuta queries y expone validaciones de existencia (`exists_by_id`, `edition_exists`) para que el service jamás toque entidades.

```python
# src/api/products/repository.py
from sqlalchemy import select, exists, func
from sqlalchemy.ext.asyncio import AsyncSession

from src.models import models


async def count(db: AsyncSession, category_id: int | None = None, search: str | None = None) -> int:
  stmt = select(func.count(models.Product.id))
  if category_id is not None:
    stmt = stmt.where(models.Product.category_id == category_id)
  if search:
    stmt = stmt.where(models.Product.name.ilike(f"%{search}%"))
  return (await db.execute(stmt)).scalar_one()


async def get_all(db: AsyncSession, page: int = 1, limit: int = 20, category_id: int | None = None, search: str | None = None) -> list[models.Product]:
  stmt = select(models.Product)
  if category_id is not None:
    stmt = stmt.where(models.Product.category_id == category_id)
  if search:
    stmt = stmt.where(models.Product.name.ilike(f"%{search}%"))
  result = await db.execute(stmt.order_by(models.Product.name).offset((page - 1) * limit).limit(limit))
  return list(result.scalars().all())


async def exists_by_name(db: AsyncSession, name: str) -> bool:
  result = await db.execute(select(exists().where(models.Product.name == name)))
  return result.scalar_one()


async def exists_by_id(db: AsyncSession, id: int) -> bool:
  result = await db.execute(select(exists().where(models.Product.id == id)))
  return result.scalar_one()


async def get_by_id(db: AsyncSession, id: int) -> models.Product | None:
  result = await db.execute(select(models.Product).where(models.Product.id == id))
  return result.scalar_one_or_none()


async def create(db: AsyncSession, data: dict) -> models.Product:
  item = models.Product(**data)
  db.add(item)
  await db.commit()
  await db.refresh(item)
  return item


async def update(db: AsyncSession, item: models.Product, data: dict) -> models.Product:
  for key, value in data.items():
    setattr(item, key, value)
  await db.commit()
  await db.refresh(item)
  return item


async def delete(db: AsyncSession, item: models.Product) -> None:
  await db.delete(item)
  await db.commit()
```

---

## 5. Modelos (SQLAlchemy 2.0 `Mapped`)

> El diseño de esquema, tipos, índices, constraints y migraciones sigue la skill **`sql`**; aquí se cubre el mapeo con SQLAlchemy sobre PostgreSQL.

- Un único `models.py` (evita imports circulares).
- Tablas con prefijo del proyecto (p. ej. `app_` o `acme_`). El mismo prefijo se usa en los tests para dropear solo tus tablas.
- Identidades: si una PK/columna es `GENERATED ALWAYS AS IDENTITY`, **no insertar valores explícitos** para esa columna (Postgres lanza `ProgrammingError`). Para idempotencia en el seed: si la columna tiene UNIQUE (`ON CONFLICT (col)`), y si NO la tiene (`INSERT ... SELECT ... WHERE NOT EXISTS`).
- `Mapped`/`mapped_column` con tipos de Python (`str | None`), no strings.
- Relaciones con `back_populates` simétricos y `order_by` para listas ordenadas.
- **Prohibido el borrado en cascada automático en ORM**: no usar `cascade="all, delete-orphan"` en `relationship` ni `ondelete="CASCADE"` en `ForeignKey`. El borrado secundario siempre debe ser **explícito** en el service/repository.
  - **Regla de dirección de la dependencia**: la cascada ilegal es la que va **desde una tabla maestra/catálogo hacia su(s) hija(s)** o hacia otras maestras (borrar `Format` NO debe eliminar `EditionFormat` ni `Edition`). El borrado de una tabla maestra puede limpiar de forma explícita solo sus **tablas puente** (relación), nunca las otras maestras que la puente referencia (borrar `Edition` puede eliminar sus `EditionFormat`, pero `Format` queda intacto).
  - **Tablas maestras reales (no puente)**: si el padre tiene hijos que no son tabla puente (p. ej. `Edition` → `Copy`), se **bloquea** el borrado con `BadRequestProblem` (patrón `has_copies`, o `exists_by_*` en copy/book).
  - **Tablas puente**: al borrar la maestra, se eliminan de forma explícita los registros de la puente asociados a ella (patrón `editions/repository.delete_formats_by_edition`: `SELECT` + `db.delete` de cada fila puente + `flush`), respetando la regla de no-cascades ORM. No des-asociar "en cascada" mediante el ORM; hacerlo explícitamente.
  - Ejemplo válido: borrar `Edition` → `delete_formats_by_edition` (limpia `wm_edition_format` de esa edición) y luego `db.delete(edition)`; `Format` no se toca. Ejemplo inválido: borrar `Format` y que se arrastre `EditionFormat`/`Edition`.
- Timestamps: `server_default=func.now()` y `onupdate=func.now()` para `updated_at`.
- FK de tablas de progreso/relaciones usuario–recurso: PK compuestas con `primary_key=True` en ambas columnas (no `id` sintético inventado).
- Monedas/precios en enteros (centavos), nunca `float`.

```python
# src/models/models.py
from datetime import datetime
from sqlalchemy import Integer, String, Boolean, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from src.core.database import Base


class Category(Base):
  __tablename__ = "app_categories"

  id: Mapped[int] = mapped_column(Integer, primary_key=True)
  name: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)

  products: Mapped[list["Product"]] = relationship(back_populates="category")


class Product(Base):
  __tablename__ = "app_products"

  id: Mapped[int] = mapped_column(Integer, primary_key=True)
  category_id: Mapped[int] = mapped_column(Integer, ForeignKey("app_categories.id"), nullable=False)
  name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
  slug: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
  price: Mapped[int] = mapped_column(Integer, nullable=False)  # en centavos, nunca float
  is_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
  created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
  updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

  category: Mapped["Category"] = relationship(back_populates="products")
```

---

## 6. DTOs (Pydantic v2)

- `AppModel` base con `ConfigDict(from_attributes=True)` → permite `model_validate(orm_object)`.
- `PaginationRequest` y `PaginationResponse[T]` compartidos en `dtos.py`.
- Tipos estrictos: fechas como `datetime` (Pydantic v2 es estricto: `str` rompe con `model_validate`), precios enteros.
- Request sin `from_attributes` (son de entrada), Response con `AppModel`.
- **Validar las FKs**: en los `*Request`, los IDs de llaves foráneas llevan `Field(ge=1)` — un `0` o negativo jamás debe llegar a la BD.
- `max_length` acotado en strings de entrada según el modelo; textos largos (`description`) con límite explícito.
- Listas opcionales de IDs (relaciones many-to-many) con `Field(default_factory=list)`.
- **Responses con `str` que pueden venir `None` desde la BD**: si el DTO de respuesta declara el campo como `str` (obligatorio) pero en la BD puede ser NULL, validar con `... if x else ""` (o el string por defecto) en el service antes de `model_validate`; si no, Pydantic lanza `ValidationError` en runtime. Alternativa: declarar el campo como `str | None`.

```python
# src/schemas/dtos.py
from datetime import datetime
from typing import Generic, TypeVar
from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class AppModel(BaseModel):
  model_config = ConfigDict(from_attributes=True)


class PaginationRequest(BaseModel):
  page: int = Field(default=1, ge=1)
  limit: int = Field(default=20, ge=1, le=100)
  search: str | None = None


class PaginationResponse(BaseModel, Generic[T]):
  page: int
  limit: int
  total: int
  items: list[T]


class CategoryResponse(AppModel):
  id: int
  name: str


class ProductRequest(BaseModel):
  category_id: int = Field(ge=1)
  name: str = Field(min_length=1, max_length=100)
  slug: str = Field(min_length=1, max_length=100)
  price: int = Field(ge=0)
  is_enabled: bool = True


class ProductResponse(AppModel):
  id: int
  category_id: int
  name: str
  slug: str
  price: int
  is_enabled: bool
  created_at: datetime
  updated_at: datetime
```

**Detalle anidado** (cuando un recurso expone una vista enriquecida): un `*DetailResponse` que hereda del Response base y agrega las listas anidadas. En el repository se carga con `selectinload` en cadena y en el service se valida con `model_validate`.

```python
class ProductDetailResponse(ProductResponse):
  category: CategoryResponse
  reviews: list["ReviewResponse"]
```

```python
# repository: carga eager en cadena (evita N+1)
result = await db.execute(
  select(models.Product)
  .options(
    joinedload(models.Product.category),
    selectinload(models.Product.reviews),
  )
  .where(models.Product.id == id)
)
entity = result.unique().scalar_one_or_none()
```

---

## 7. Errores — RFC 9457 (ProblemDetails) con `fastapi-problem`

El patrón central de errores. Todas las excepciones de negocio heredan de clases RFC 9457 y se serializan como:

```json
{ "type": "not-found", "title": "Resource not found.", "status": 404, "detail": "Product not found" }
```

con `Content-Type: application/problem+json`.

### 7.1 Excepciones (`src/core/exceptions.py`)

```python
from fastapi import status
from rfc9457 import BadRequestProblem, ForbiddenProblem, NotFoundProblem, Problem, UnauthorisedProblem


class AppError(Problem):
  def __init__(self, message: str, status_code: int = status.HTTP_400_BAD_REQUEST):
    self.message = message
    super().__init__(title=message, detail=message, status=status_code, type_="app-error")


class NotFoundError(NotFoundProblem):
  type_ = "not-found"
  title = "Resource not found."

  def __init__(self, entity: str = "Resource"):
    super().__init__(detail=f"{entity} not found")
    self.message = self.detail


class DuplicateNameError(BadRequestProblem):
  type_ = "duplicate-name"
  title = "Duplicate resource."

  def __init__(self, name: str):
    super().__init__(detail=f"'{name}' already exists")
    self.message = self.detail


class UnauthorizedError(UnauthorisedProblem):
  type_ = "unauthorized"
  title = "Unauthorized."

  def __init__(self, message: str = "Invalid or expired token"):
    super().__init__(detail=message)
    self.message = message


class ForbiddenError(ForbiddenProblem):
  type_ = "forbidden"
  title = "Forbidden."

  def __init__(self, message: str = "Insufficient permissions"):
    super().__init__(detail=message)
    self.message = message


class InvalidApiKeyError(UnauthorisedProblem):
  type_ = "invalid-api-key"
  title = "Invalid API key."

  def __init__(self, message: str = "Invalid API Key"):
    super().__init__(detail=message)
    self.message = message
```

### 7.2 Configuración en `main.py`

```python
from fastapi_problem.handler import add_exception_handler, new_exception_handler
from rfc9457 import BadRequestProblem, Problem, ServerProblem, UnprocessableProblem
from slowapi.errors import RateLimitExceeded


class RequestValidationProblem(UnprocessableProblem):
  type_ = "request-validation-failed"
  title = "Request validation error."

  def __init__(self, errors=None, **kwargs):
    super().__init__(errors=errors, **kwargs)
    self.detail = "; ".join(str(e.get("msg", "")) for e in errors) if errors else self.title


class InternalServerErrorProblem(ServerProblem):
  type_ = "internal-server-error"
  title = "Internal server error."

  def __init__(self, detail=None, **kwargs):
    super().__init__(detail="Internal server error", **kwargs)


class RateLimitProblem(BadRequestProblem):
  type_ = "rate-limit-exceeded"
  title = "Rate limit exceeded."
  status = 429


def rate_limit_handler(eh, request: Request, exc: RateLimitExceeded):
  headers = None
  if hasattr(request.state, "view_rate_limit"):
    response = request.app.state.limiter._inject_headers(JSONResponse({}), request.state.view_rate_limit)
    headers = dict(response.headers)
  return RateLimitProblem(detail=f"Rate limit exceeded: {exc.detail}", headers=headers)


def log_problem(request: Request, exc: Exception):
  if isinstance(exc, Problem) and exc.status < 500:
    logger.warning("%s: %s", exc.title, exc.detail, extra={"props": {"status_code": exc.status}})


eh = new_exception_handler(
  logger=logger,
  unhandled_wrappers={"422": RequestValidationProblem, "500": InternalServerErrorProblem},
  handlers={RateLimitExceeded: rate_limit_handler},
  pre_hooks=[log_problem],
)
add_exception_handler(app, eh)
app.add_exception_handler(RateLimitExceeded, eh)
```

**Reglas**:
- Los services lanzan errores semánticos (`NotFoundError("Product")`), nunca `HTTPException`.
- No exponer detalles internos en el 500 (respuesta genérica, el detalle real va al log).
- Compatibilidad con frontend: el campo `detail` es string en todos los casos; el 422 conserva el array `errors` original.

---

## 8. Auth transversal — `references/auth.md`

Auth transversal (OAuth + JWT + refresh rotation, API Key global, rol resuelto desde la BD) vive en **`references/auth.md`** de esta skill. Léelo antes de tocar autenticación, endpoints protegidos o roles.

## 9. Uploads de imágenes — `references/uploads.md`

Uploads (multipart + servicio de almacenamiento tipo Cloudinary/S3) vive en **`references/uploads.md`**.

## 10. Email transaccional — `references/email.md`

Email transaccional (patrón de cliente externo encapsulado por feature, p. ej. Brevo) vive en **`references/email.md`**.

## 11. Rate limiting — `references/rate-limiting.md`

Rate limiting (slowapi, clave por identidad) vive en **`references/rate-limiting.md`**.

---

## 12. Configuración y logging

### 12.1 `src/core/config.py` (pydantic-settings)

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

### 12.2 `src/core/database.py`

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

### 12.3 `src/core/logger.py` (JSON + request_id por petición)

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

---

## 13. Tests — `references/tests.md`

Tests (BD real PostgreSQL aislada por prefijo, `conftest.py`, `TEST_DATABASE_URL`, marcador `live`) viven en **`references/tests.md`**.

---

## 14. Checklist final (¿esto es SENIOR?)

Antes de dar una API por terminada:

- [ ] Estructura feature-based (`routes/service/repository` por carpeta)
- [ ] `core/` separado para transversal (config, database, security, exceptions, logger, limiter, dependencies)
- [ ] Un solo `models.py` y un solo `dtos.py` (DTOs locales solo en `schemas.py` del feature)
- [ ] Paginación unificada (`PaginationRequest`/`PaginationResponse[T]`) en todos los listados
- [ ] Errores RFC 9457 (`fastapi-problem`), nunca `HTTPException` en rutas
- [ ] Auth: el rol se lee de la BD por request; `require_admin`/`require_user` declarativos; refresh rotation; API Key global; `user_id` extraído del token, nunca del body
- [ ] Cross-feature solo service→service (sin imports a repository de otra feature); `commit` solo en repositories
- [ ] Service sin imports de `models` (entidades ORM); cross-feature con DTOs o value-objects (jamás entidades); validaciones de existencia vía repository (`edition_exists`, `copy_status_exists`)
- [ ] Borrado sin cascades: todo `delete` valida sus dependencias con otras tablas y bloquea con `BadRequestProblem` si hay hijos (sin `cascade`/`ondelete="CASCADE"`)
- [ ] Uploads: borra la imagen anterior antes de subir, `delete()` limpia el storage, `extract_public_id` salta transformaciones
- [ ] Rate limiting por identidad (JWT→`user:{id}`, si no→IP) + límite por endpoint si es formulario público
- [ ] Logging JSON con `request_id` por petición
- [ ] Logs con `logger` (nunca `print()`); excepciones con `exc_info=True` (o `logger.exception`) y contexto en el mensaje (ej. `notification_id`); helper centralizado si el mismo fallo se loguea en varios puntos
- [ ] Tests con BD real, que dropean solo sus tablas (prefijo), seed de roles/admin, caso de error por recurso
- [ ] Cliente externo por uso: 1 feature → dentro del feature (`contact/brevo.py`), ≥2 features → `core/`
- [ ] Errores de proveedor externo mapeados por status (401/403→config, 429→429, resto→502) y respuesta logueada en éxito
- [ ] Tests live aislados (`@pytest.mark.live`) excluidos por defecto (`-m "not live"`)
- [ ] `requirements.txt` con versiones fijas; `.env_demo` como plantilla
- [ ] DTOs con `datetime` (no `str`), precios/monedas en enteros, FKs con `Field(ge=1)`, `max_length` acotado
- [ ] `selectinload`/`joinedload` para relaciones eager (evita N+1)
- [ ] Seed idempotente (FKs por natural keys)

---

## 15. Errores comunes (anti-patrones)

| Anti-patrón | Por qué evitarlo |
|-------------|------------------|
| `HTTPException(status_code=404, detail=...)` dentro de rutas | Duplica lógica y rompe el formato RFC 9457 |
| `print()` para registrar errores | Ruido no estructurado, sin `request_id` ni nivel ni stack trace; usar el `logger` del proyecto (`src.core.logger`) y `logger.error(..., exc_info=True)`. Un helper compartido (ej. `_log_email_failure`) evita 5 bloques duplicados |
| Llamar a un proveedor externo sin `raise_for_status()` | Los 4xx/5xx se devuelven "exitosos" y se procesa el body de error como éxito (fallo silencioso). `response.raise_for_status()` convierte el status en excepción, y loguear `status_code` + body anticipa el diagnóstico |
| Un `crud.py` global | No escala: mezcla dominios y genera acoplamiento |
| `from sqlalchemy import delete` + función local `async def delete` | Name shadowing: la función local opaca el import → `NameError`/`TypeError` al operar. Renombrar el import (`delete as sqla_delete`) |
| DTO de respuesta sin `from_attributes=True` | `model_validate(orm_object)` falla (no lee atributos) → 500 en runtime. Los responses llevan `ConfigDict(from_attributes=True)` |
| Lógica en la ruta (validaciones, queries) | Imposible de testear unitariamente y de reutilizar |
| Un service que importa el repository de **otra** feature | Acopla la feature por implementación; romper esa tabla rompe todo. Ir siempre por el service (service→service) |
| Un service que importa `src.models.models` | Mezcla la capa de persistencia con la de aplicación: el service queda atado al ORM. Solo el repository importa modelos; el service trabaja con DTOs y value-objects |
| `db.get(models.X, ...)` o `models.X(**data)`/`db.add` en el service | Queries y construcción de entidades en la capa de aplicación. Mover al repository: validaciones de existencia (`edition_exists`, `copy_status_exists`) y `create`/`create_many` reciben dicts |
| Pasar entidades ORM entre features (service→service) | Acopla features a la representación de la BD; compartir DTOs o value-objects (`EmailData`) |
| `db.commit()` en el service | El commit es responsabilidad de la capa de datos; en el service se pierde la atomicidad (varios commits sueltos) y se mezclan responsabilidades |
| **Borrado en cascada** (`cascade="all, delete-orphan"` o `ondelete="CASCADE"`) | Borra datos dependientes sin validación y sin aviso; rompe la integridad referencial. Con PK compuestas en tablas puente lanza `AssertionError` en SQLAlchemy. Todo borrado debe validar dependencias y bloquearte (`BadRequestProblem`) si existen |
| **Confiar en el rol del token JWT** (sin leerlo de la BD) | Un admin destituido sigue con acceso hasta que expire el token (2h); un usuario eliminado sigue activo. Leer el rol real en cada request |
| `Annotated[Model, Query()]` para paginación + otros query params | Rompe con 422 en FastAPI 0.139+ |
| `model_validate` con `str` en fechas | Pydantic v2 falla silenciosamente/estricto |
| Monedas/precios como `float` | Errores de redondeo; usar enteros (centavos) |
| Dropear `drop_all` en tests sobre BD compartida | Destruye datos de otros proyectos |
| `user_id` desde el body en endpoints autenticados | Cualquiera podría actuar como otro usuario |
| Pasar la query del frontend directo al ORM | SQL injection / N+1 |
| No paginar listados | El payload crece sin límite y mata la UX |
| FKs sin `Field(ge=1)` en los DTOs de entrada | Un `0` o `-1` llega a la BD y rompe la integridad referencial con un error confuso |
| Llamadas reales a servicios externos en tests | Envían correos/cobran/suben archivos en cada suite; aislar con `@pytest.mark.live` |
| SDK oficial del proveedor (`brevo_python`) | Una lib más que fijar, pinchar y actualizar; `httpx` async basta para 1-2 endpoints |
| `502` genérico en fallo de proveedor | Oculta la causa real; mapear por status y loguear el detalle (`messageId`, body del error) |
| Interpolar contenido del usuario en el HTML del email | HTML injection; escapar siempre |
