## 10. Email transaccional (Brevo) — patrón de cliente externo por uso

Un feature que envía correo NO mete el proveedor en `core/` si es el único que lo usa: encapsula el cliente dentro del feature (`api/contact/brevo.py`), igual que `auth/google_service.py`. Si otro feature lo necesitara, se migra a `core/`.

- Config en `src/core/config.py`: `BREVO_API_KEY`, `BREVO_FROM_EMAIL`, `BREVO_FROM_NAME`, `TEST_BREVO_EMAIL`.
- Cliente con `httpx.AsyncClient` (sin librería extra del proveedor) contra `POST https://api.brevo.com/v3/smtp/email`, header `api-key: BREVO_API_KEY`. **201 = éxito** y devuelve `messageId`.
- La API key de Brevo se crea en el tab **"API Keys & MCP"** (no la SMTP key, no marcar MCP); empieza con `xkeysib-` y solo se muestra una vez.
- DTOs locales en `schemas.py` del feature (`ContactRequest`, `ContactResponse`), nunca en `dtos.py`.
- El email del remitente sale del **usuario autenticado** (vía `users_service.get_by_id`), no de un campo del form.

```python
# src/api/contact/brevo.py — cliente encapsulado (httpx async, sin SDK del proveedor)
import httpx
from src.core.config import settings
from src.core.logger import logger

BREVO_URL = "https://api.brevo.com/v3/smtp/email"


async def _send_email(to_email: str, subject: str, html: str, reply_to: str | None = None) -> str:
  payload = {
    "sender": {"email": settings.BREVO_FROM_EMAIL, "name": settings.BREVO_FROM_NAME},
    "to": [{"email": to_email}],
    "subject": subject,
    "htmlContent": html,
  }
  if reply_to:
    payload["replyTo"] = {"email": reply_to, "name": reply_to}
  async with httpx.AsyncClient(timeout=30) as client:
    response = await client.post(BREVO_URL, json=payload, headers={"api-key": settings.BREVO_API_KEY})
  if response.status_code != 201:
    raise _raise_brevo_error(response)
  message_id = response.json().get("messageId", "")
  logger.info("Email sent", extra={"messageId": message_id, "to": to_email})
  return message_id
```

**Mapeo de errores del proveedor** (nunca un 502 genérico que trague el detalle): `401/403` → 500 (config/credenciales), `429` → 429 (rate limit del proveedor), resto → 502.

```python
def _raise_brevo_error(response: httpx.Response) -> Exception:
  if response.status_code in (401, 403):
    return BrevoConfigurationError()
  if response.status_code == 429:
    return BrevoRateLimitError()
  return BrevoProviderError(detail=response.text)
```

- Template HTML **con estilos inline** (los clientes de correo ignoran `<style>`): tablas para el layout, colores de marca como constantes, y el link del remitente en el color de marca (no depender del azul de Gmail/Outlook).
- **Escapar el contenido del usuario** en el HTML (nunca interpolar crudo).
- Endpoint de formulario público → `@limiter.limit("5/minute")` además del default global.
- Tests: unitarios mockean `_send_email`; los de envío real van en `test_contact_live.py` con `@pytest.mark.live` (excluidos por defecto).
