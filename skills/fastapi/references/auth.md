## 8. Auth transversal (OAuth + JWT + Refresh Rotation)

Siempre presente en cualquier API: se reutiliza en todos los proyectos. Componentes:

### 8.1 `src/core/security.py` — JWT identifica, el rol se lee de la BD

**Punto clave**: el rol embebido en el token es una *pista*, no una autoridad. En cada request protegido se lee el rol real del usuario desde la BD (`users_service.get_role_name_by_id`): un cambio de rol, una baja de usuario o un refresh de permisos se refleja al instante, sin esperar que expire el token (2h).

```python
from datetime import datetime, timedelta, timezone
from typing import Callable, Optional
from uuid import UUID

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.users import service as users_service
from src.core.config import settings
from src.core.database import get_db
from src.core.exceptions import ForbiddenError, UnauthorizedError

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 2
bearer_scheme = HTTPBearer(auto_error=False)


def create_access_token(user_id: UUID, role: str) -> str:
  now = datetime.now(tz=timezone.utc)
  payload = {
    "sub": str(user_id),
    "role": role,
    "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    "iat": now,
  }
  return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> dict:
  try:
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
  except JWTError:
    raise UnauthorizedError()


def get_current_user(required_roles: Optional[list[str]] = None):
  async def _get_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
  ):
    if credentials is None:
      raise UnauthorizedError()

    payload = verify_token(credentials.credentials)

    try:
      user_id = UUID(payload["sub"])
    except (ValueError, KeyError, TypeError):
      raise UnauthorizedError()

    # El rol REAL se lee de la BD, no se confía en el rol del token.
    role = await users_service.get_role_name_by_id(db, user_id)
    if role is None:
      raise UnauthorizedError(message="User no longer exists")

    if required_roles is not None and role not in required_roles:
      raise ForbiddenError()

    payload["role"] = role
    return payload
  return _get_user
```

### 8.2 `src/core/dependencies.py` (API Key global + roles)

```python
from fastapi import Header, Depends

from src.core.config import settings
from src.core.exceptions import InvalidApiKeyError
from src.core.security import get_current_user


async def verify_api_key(x_api_key: str = Header(..., alias="X-API-Key")):
  if x_api_key != settings.API_KEY:
    raise InvalidApiKeyError()
  return True


require_admin = get_current_user(required_roles=["admin"])
require_user = get_current_user()
```

### 8.3 Flujo de login (Google OAuth) en `src/api/auth/`

El `users.service.get_or_create_user` recibe identidad primaria (`google_sub`) y email. `verify_google_token` valida contra Google **aud == GOOGLE_CLIENT_ID** (sin ese check, cualquier token de otra app de Google da acceso).

```python
# routes.py — router con dependencies=[Depends(verify_api_key)]
@router.post("/google", response_model=schemas.AuthGoogleResponse, status_code=HTTP_200_OK)
@limiter.limit("10/minute")  # siempre rate-limit el login
async def auth_google(request: Request, auth_data: schemas.AuthGoogleRequest, db: AsyncSession = Depends(database.get_db)):
  return await service.auth_service(db, auth_data.googleToken)
```

```python
# google_service.py — cliente OAuth (httpx async, sin SDK del proveedor)
async def verify_google_token(access_token: str) -> schemas.GoogleUserInfo:
  async with httpx.AsyncClient(timeout=10) as client:
    response = await client.get(
      GOOGLE_TOKEN_INFO_URL,
      params={"access_token": access_token},
    )
  if response.status_code != 200:
    raise UnauthorizedError(message="Invalid Google token")

  token_info = response.json()
  if settings.GOOGLE_CLIENT_ID and token_info.get("aud") != settings.GOOGLE_CLIENT_ID:
    raise UnauthorizedError(message="Invalid Google token")

  email_verified = token_info.get("email_verified")
  if email_verified not in (True, "true"):
    raise UnauthorizedError(message="Email not verified")

  # /tokeninfo con un access token no garantiza name/picture: si faltan, se
  # consulta /userinfo (misma validez: el token ya fue validado por aud).
  return schemas.GoogleUserInfo(google_id=token_info["sub"], email=token_info["email"], ...)
```

```python
# service.py — orquesta el flujo completo
async def auth_service(db: AsyncSession, google_token: str) -> schemas.AuthGoogleResponse:
  info = await google_service.verify_google_token(google_token)

  user = await users_service.get_or_create_user(db, info.email, info.google_id)

  token = security.create_access_token(user.id, user.role.name)
  refresh_token = secrets.token_urlsafe(32)
  expires_at = datetime.now(tz=timezone.utc) + timedelta(days=REFRESH_TOKEN_DAYS)
  # Guardar SOLO el hash: si la BD se filtra, los refresh tokens no son usables.
  await session_repository.create(db, user.id, hash_token(refresh_token), expires_at)

  return schemas.AuthGoogleResponse(token=token, refresh_token=refresh_token, user=...)
```

```python
# users/service.py — get_or_create_user (identidad primaria por google_sub)
async def get_or_create_user(db: AsyncSession, email: str, google_id: str) -> dtos.UserResponse:
  entity = await repository.get_by_google_sub(db, google_id)
  if not entity:
    entity = await repository.get_by_email(db, email)

  if not entity:
    role = await roles_service.get_by_name(db, DEFAULT_ROLE_NAME)  # "user"
    if not role:
      raise NotFoundError("Role")  # el rol por defecto se resuelve por nombre, no con ID en duro
    entity = await repository.create(db, {"email": email, "role_id": role.id, "google_sub": google_id})
  return dtos.UserResponse.model_validate(entity)
```

```python
# refresh rotation: el refresh viejo se revoca y se emite uno nuevo
async def refresh_session(db, refresh_token):
  # Buscar por hash (nunca se guarda el token en claro).
  session = await session_repository.get_by_token_hash(db, hash_token(refresh_token))
  if not session or session.expires_at < datetime.now(tz=timezone.utc):
    raise UnauthorizedError("Invalid or expired refresh token")
  user_id, role_name = session.user_id, session.user.role.name
  # Rotación ATÓMICA: revocar de forma condicional (UPDATE ... SET revoked=true WHERE id=:id AND revoked=false).
  # Si no afecta filas, el token ya se usó → dos refresh concurrentes no emiten dos pares válidos.
  if not await session_repository.revoke_if_active(db, session.id):
    raise UnauthorizedError("Invalid or expired refresh token")
  new_refresh = secrets.token_urlsafe(32)
  await session_repository.create(db, user_id, hash_token(new_refresh), datetime.now(tz=timezone.utc) + timedelta(days=REFRESH_TOKEN_DAYS))
  return schemas.AuthRefreshResponse(token=security.create_access_token(user_id, role_name), refresh_token=new_refresh)
```

> **Refresh token — decisión explícita de seguridad y concurrencia**:
> - **Almacenar el hash** (`sha256(token)`), nunca el token en claro; declarar `UNIQUE` sobre esa columna.
> - **Rotación de un solo uso y atómica**: la revocación debe ser condicional (`UPDATE … WHERE revoked = false`); si afecta 0 filas, rechazar.
> - **Detección de reuso**: si llega un token ya revocado, revocar toda la familia de sesiones del usuario (posible robo).

### 8.4 Endpoints de usuario autenticado

El `user_id` **nunca viene del body**: se extrae del token.

```python
# src/api/user_favorites/routes.py (ejemplo transversal de feature "del usuario")
from uuid import UUID
from fastapi import APIRouter, Depends

from src.core.dependencies import verify_api_key, require_user

router = APIRouter(prefix="/user-favorites", tags=["user-favorites"], dependencies=[Depends(verify_api_key)])


def get_user_id(payload: dict = Depends(require_user)) -> UUID:
  return UUID(payload["sub"])


@router.post("/", response_model=dtos.UserFavoriteResponse, status_code=201)
async def add_to_favorites(data: dtos.UserFavoriteRequest, user_id: UUID = Depends(get_user_id), db=Depends(get_db)):
  return await service.create(db, user_id, data.product_id)
```

**Regla de dependencia**: la dependency `get_user_id` es del feature (rutas del feature), **no** de `core/dependencies.py` — la reutilización del feature evita que `core/` se acople a dominios.

Patrón `upsert` en el repository (no falla por PK duplicada): si la fila existe se actualiza, si no se crea.

**Features `roles`**: catálogo de roles sin routes (solo `repository.py` + `service.py`). Lo consumen `users` y `security` (resolución de rol por nombre y de nombre de rol del usuario). El `"role"` default se resuelve por **nombre** (`service.get_by_name(db, "user")`), nunca con ID en duro.
