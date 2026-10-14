# Errores — RFC 9457 (ProblemDetails) con `fastapi-problem`

El patrón central de errores. Todas las excepciones de negocio heredan de clases RFC 9457 y se serializan como:

```json
{ "type": "not-found", "title": "Resource not found.", "status": 404, "detail": "Product not found" }
```

con `Content-Type: application/problem+json`.

## Excepciones (`src/core/exceptions.py`)

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

## Configuración en `main.py`

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

## Reglas

- Los services lanzan errores semánticos (`NotFoundError("Product")`), nunca `HTTPException`.
- No exponer detalles internos en el 500 (respuesta genérica, el detalle real va al log).
- Compatibilidad con frontend: el campo `detail` es string en todos los casos; el 422 conserva el array `errors` original.
