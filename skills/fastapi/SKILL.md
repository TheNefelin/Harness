---
name: fastapi
description: Patrón senior para APIs REST en Python con FastAPI, SQLAlchemy 2.1 async y PostgreSQL. Usar al crear, modificar o revisar una API FastAPI: endpoints, modelos, servicios, auth, uploads, email o testing. NO para APIs .NET ('dotnet'), esquema/índices/motores ('sql'/'nosql') ni frontend ('angular'/'astro').
---

# SKILL: API FastAPI en Python — Patrón Senior (transversal)

Guía de referencia para construir APIs REST con **FastAPI + SQLAlchemy 2.1 (async) + PostgreSQL**, siguiendo una arquitectura y convenciones senior validadas en producción. Es **transversal**: los ejemplos son genéricos (CRUD, catálogos, auth, uploads, email) y aplican a cualquier dominio — e-commerce, SaaS, contenido, fintech, lo que sea.

Este archivo es un **skill**: se lee para replicar el patrón en cualquier API nueva. No es una receta dogmática, es la lista de decisiones que convierten un CRUD simple en un backend mantenible.

**Servicios externos (todos opcionales según el proyecto, y por eso se configuran como tal):**
- **Auth**: Google OAuth (`api/auth/google_service.py`) + JWT + refresh rotation — reemplazable por cualquier proveedor OAuth.
- **Imágenes**: Cloudinary (`core/cloudinary.py`) — el patrón de almacenamiento es el mismo para cualquier servicio (S3, etcétera).
- **Email transaccional**: Brevo (`api/contact/brevo.py`) — REST API `/v3/smtp/email` con httpx async; el patrón aplica a cualquier proveedor.

**Referencias** (se leen bajo demanda, rutas relativas a esta skill): `references/auth.md`, `references/uploads.md`, `references/email.md`, `references/rate-limiting.md`, `references/tests.md`, `references/ejemplo-crud.md`, `references/dtos.md`, `references/errores-rfc9457.md`, `references/configuracion-logging.md`.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| API en .NET / C# / ASP.NET Core | `dotnet` |
| Diseño de esquema, tipos, índices, constraints o migraciones del motor | `sql` (SQL Server / PostgreSQL) o `nosql` |
| Frontend Angular o Astro | `angular` / `astro` |
| Diseño visual / mockups previos a implementar | `ui-ux-mockup` |

El **cómo** se escribe la API (feature-based, route→service→repository, DTOs, errores RFC 9457) vive aquí; el **esquema de la BD** y el mapeo con SQLAlchemy se apoyan en `sql`.

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
| ORM | SQLAlchemy 2.1 (estilo `Mapped`/`mapped_column`) + `asyncpg` |
| Validación | Pydantic v2 (`from_attributes=True`) |
| Auth | Google OAuth (opcional), `python-jose` (JWT HS256), refresh token rotation |
| Errores | `fastapi-problem` (RFC 9457) |
| Rate limit | `slowapi` |
| Logging | Logging estándar + formatter JSON + `ContextVar` para `request_id` |
| Imágenes | Cloudinary (o cualquier servicio: el patrón es el mismo) |
| Email transaccional | Brevo REST API (`/v3/smtp/email`) con `httpx` async (el patrón aplica a cualquier proveedor) |
| Tests | `pytest` + `pytest-asyncio` + `httpx` |

> **Frescura (verificado 2026-10-13 en PyPI):** FastAPI **0.143.0**, SQLAlchemy **2.1.4**, Pydantic **2.14.1**; PostgreSQL **18** (estable desde 2025-09-25). El estilo `Mapped`/`mapped_column` y las APIs async siguen vigentes en 2.1.

---

## 3. Estructura de carpetas (plantilla)

```text
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

> **Ejemplo CRUD completo** (route, service y repository de una feature `products`): `references/ejemplo-crud.md`.

### 4.1 Route (decide HTTP)
- Solo declara `APIRouter(prefix, tags, dependencies=[Depends(verify_api_key)])`, endpoints y delega al service.
- **Nunca** hace queries, **nunca** arma `JSONResponse` de error, **nunca** valida reglas de negocio.
- `status_code` explícito por endpoint (`HTTP_200_OK/201/204`).
- Endpoints de escritura agregan `_: dict = Depends(require_admin)` (o `require_user` para endpoints de usuario autenticado).
- Paginación se inyecta con `params: Annotated[PaginationRequest, Depends()]`. **NO** usar `Annotated[Model, Query()]` (en FastAPI reciente no se combina con otros query params y rompe con 422).

### 4.2 Service (orquesta y aplica reglas de negocio)
- Llama al repository, valida, lanza errores de negocio, mapea a DTOs con `model_validate`.
- **El service decide el error**, el repository solo devuelve datos (`None` si no existe).
- Los `await db.commit()` viven en el repository (capa de datos), nunca en el service. Si una operación necesita varios cambios atómicos, el repository expone un único `delete_by_*`/`remove_*` que los ejecuta y commitea juntos.
- Helpers de validación de FK se exponen para otros features: `ensure_product_exists(db, id)`.
- **Regla cross-feature**: si una feature necesita datos de otra, se importa **su service** (`from src.api.categories import service as categories_service` → `categories_service.exists_by_id(...)`), nunca su repository directamente.
- **Regla de capa de datos**: el service **NUNCA importa `src.models.models`** (entidades ORM). Solo el repository toca entidades. El service tipa y retorna únicamente DTOs (`dtos.*`); si necesita la entidad de su propia feature, el repository se la devuelve y el service la mapea. Si necesita datos de otra feature, usa su service (que devuelve DTOs).
- **Cross-feature con entidades**: jamás se pasan entidades ORM entre services. Se comparten **DTOs o value-objects** (`dataclass` de `core`/`schemas`, p. ej. `src.core.email.EmailData`): el caller mapea su propia entidad al value-object y el receptor solo conoce el contrato de datos. Queries de validación de existencia/FK → métodos del repository propio (`edition_exists`, `copy_status_exists`), nunca `db.get(models.X, ...)` en el service.

### 4.3 Repository (solo queries SQLAlchemy)
- Una función por operación: `count`, `get_all`, `get_by_id`, `exists_by_name`, `exists_by_id`, `create`, `update`, `delete`.
- `create`/`update` reciben `dict` (de `data.model_dump()`) y devuelven el modelo refrescado.
- Búsqueda con `ilike` (se omite si `None`/vacío).
- Filtros específicos (p. ej. `category_id`) van como parámetros, **no** dentro del DTO de paginación.
- `commit()` + `refresh()` aquí, no en el service.
- **Es la única capa que importa `src.models.models`**: construye entidades (`models.X(**data)`), ejecuta queries y expone validaciones de existencia (`exists_by_id`, `edition_exists`) para que el service jamás toque entidades.

---

## 5. Modelos (SQLAlchemy 2.1 `Mapped`)

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

El código completo (`dtos.py`, incluido el `*DetailResponse` anidado y el `selectinload` en cadena para evitar N+1) está en **`references/dtos.md`**.

---

## 7. Errores — RFC 9457 (ProblemDetails) con `fastapi-problem`

El patrón central de errores. Todas las excepciones de negocio heredan de clases RFC 9457 y se serializan como:

```json
{ "type": "not-found", "title": "Resource not found.", "status": 404, "detail": "Product not found" }
```

con `Content-Type: application/problem+json`. El código de las excepciones (`src/core/exceptions.py`) y la configuración del handler en `main.py` (wrappers 422/500, handler de rate limit y pre-hook de logging) está en **`references/errores-rfc9457.md`**.

**Reglas:**
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

Config con **pydantic-settings**: todo lo externo es **opcional** (el proyecto decide qué integra); las variables `TEST_*` son `None` por defecto y solo las leen las pruebas. Las requeridas (`DATABASE_URL`, `SECRET_KEY`, `API_KEY`, `CORS_ORIGINS`) van sin default y fallan al arrancar si faltan.

- `src/core/config.py`: `Settings(BaseSettings)` + `@property cors_origins_list` (parsea `CORS_ORIGINS` como JSON).
- `src/core/database.py`: `create_async_engine(..., pool_pre_ping=True)`, `async_sessionmaker`, `get_db()` que hace `yield`.
- `src/core/logger.py`: formatter JSON + `ContextVar` para `request_id`; middleware en `main.py` que setea el `request_id` y loguea método, path, status y duración.

El código de los tres archivos y el middleware está en **`references/configuracion-logging.md`**.

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

---

## 16. Fuentes

- **ProblemDetails / errores HTTP**: IETF *RFC 9457* (Problem Details for HTTP APIs).
- **JWT**: IETF *RFC 8725* (JSON Web Token Best Current Practices).
- **Config por entorno**: *The Twelve-Factor App* (`12factor.net`), factor III (config).
- **Stack**: documentación oficial de FastAPI (`fastapi.tiangolo.com`), SQLAlchemy (`docs.sqlalchemy.org`) y Pydantic (`docs.pydantic.dev`).
