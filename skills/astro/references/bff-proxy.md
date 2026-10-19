# Proxy universal BFF (`pages/api/proxy/[...path].ts`)

> Detalle de la sección **Proxy universal BFF** de la skill `astro`. El corazón del patrón: una sola ruta que traduce **toda** la comunicación con el backend.

**Reglas de oro:**
- **Único lugar** que lee `API_URL` y `API_KEY` de env.
- `buildHeaders()` agrega `X-API-Key` (origen) y **reenvía el `Authorization` entrante** (Bear del usuario). El front solo manda el Bear, nunca la API key.
- **Sin try/catch que trague el status code**: la respuesta se devuelve con su status intacto.
- GET no lleva body; 204 se responde sin body.

```ts
// src/pages/api/proxy/[...path].ts
const API_URL = import.meta.env.API_URL;
const API_KEY = import.meta.env.API_KEY;
const REFRESH_COOKIE = 'gg_refresh';

function getPath(url: URL) { return url.pathname.replace('/api/proxy/', ''); }

function buildHeaders(request: Request, extra?: Record<string, string>) {
  const headers = { 'X-API-Key': API_KEY, ...extra };
  const auth = request.headers.get('Authorization');
  if (auth) headers['Authorization'] = auth;
  return headers;
}

export const GET: APIRoute = async ({ url, request }) => {
  const response = await fetch(`${API_URL}/${getPath(url)}${url.search}`, { headers: buildHeaders(request) });
  return proxyResponse(response); // status intacto, 204 sin body
};
```

## BFF de cookies auth (refresh_token nunca en localStorage)

Los endpoints `/auth/google`, `/auth/refresh` y `/auth/logout` se manejan **especial** en el POST del proxy:

```ts
export const POST: APIRoute = async ({ url, request, cookies }) => {
  const path = getPath(url);

  if (path === 'auth/google') { /* body → backend; si trae refresh_token lo guarda en cookie y lo quita del body */ }
  if (path === 'auth/refresh') { /* lee el refresh_token DE LA COOKIE y lo manda al backend */ }
  if (path === 'auth/logout')  { /* revoca en el backend + borra la cookie */ }
  // resto: POST genérico al backend
};
```

```ts
function cookieOptions() {
  return { httpOnly: true, secure: import.meta.env.PROD, sameSite: 'lax' as const, path: '/' };
}

async function handleAuthResponse(cookies: AstroCookies, response: globalThis.Response): Promise<Response> {
  const text = await response.text();
  if (!response.ok || !text) return proxyResponse(response, text);
  const data = JSON.parse(text);
  if (data.refresh_token) {
    cookies.set(REFRESH_COOKIE, String(data.refresh_token), cookieOptions());
    const { refresh_token: _unused, ...rest } = data; // el navegador NUNCA ve el refresh_token
    return jsonResponse(rest, response.status);
  }
  return jsonResponse(data, response.status);
}
```

**Por qué es senior**: el refresh token queda `HttpOnly` (invisible para JavaScript, inmune a XSS). El front solo persiste `access_token` + `user` en `localStorage` — y eso con expiración chequeada.
