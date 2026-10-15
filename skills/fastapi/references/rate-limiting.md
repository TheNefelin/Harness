## 11. Rate limiting (slowapi) — clave por identidad

```python
# src/core/limiter.py
from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from src.core.security import verify_token


def rate_limit_key(request: Request) -> str:
  # Si el request trae JWT, el límite es POR USUARIO (user:{id}); si no, por IP.
  auth_header = request.headers.get("authorization", "")
  if auth_header.lower().startswith("bearer "):
    try:
      payload = verify_token(auth_header.split(" ")[1])
      user_id = payload.get("sub")
      if user_id:
        return f"user:{user_id}"
    except Exception:
      pass
  return get_remote_address(request)


limiter = Limiter(key_func=rate_limit_key, default_limits=["100/minute"])
```

> **Detrás de proxy**: `get_remote_address` usa la IP de la conexión, no la del cliente final. Hay que configurar proxies confiables (`--forwarded-allow-ips` en uvicorn o `ProxyHeadersMiddleware`); sin eso todos comparten la IP del proxy (o el header es falsificable).

```python
# main.py
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)

@app.get("/health")
@limiter.exempt
async def health():
  return {"status": "ok"}
```

- Default global `100/minute`; `@limiter.limit("10/minute")` en auth; `@limiter.limit("5/minute")` en endpoints de formularios públicos (p. ej. `POST /contact`).
- El handler de `RateLimitExceeded` está integrado en el manejo de errores RFC 9457 (sección 7.2) y conserva los headers `X-RateLimit-*`.
- En los tests, `limiter.reset()` en un fixture autouse evita que el límite se acumule entre tests.
