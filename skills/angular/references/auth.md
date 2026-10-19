# Auth (CSR y SSR)

> Detalle de la sección **Auth** de la skill `angular`. Léelo al implementar login, sesión, interceptores o manejo de tokens.

El patrón de auth difiere según el modo.

## [CSR] — Auth directo

- La API se consume directo desde `environment.apiUrl`; el `authInterceptor` añade `Authorization: Bearer <token>`.
- El token se guarda en el navegador (`localStorage` o `sessionStorage` según la app; `localStorage` sobrevive al cierre de pestaña).
- `authInterceptor` (funcional, `HttpInterceptorFn`): lee el token y clona el request con el header.
- Guardo simple: no hay multi-tenant ni proxy.

## [SSR] — Auth multi-tenant (por namespace)

```text
GET /ssr-api/config                    → { googleClientIds } (mapa por namespace)
POST /ssr-api/{namespace}/auth/google  → login con el client ID de ese namespace
GET/POST/DELETE /ssr-api/{namespace}/{resource}  → CRUD con Bearer del namespace
```

- **Sesión**: `sessionStorage` con prefijo `auth.{namespace}.access_token/refresh_token/user` — sobrevive a F5, muere al cerrar la pestaña.
- **⚠️ Seguridad (XSS)**: `sessionStorage`/`localStorage` **no** aíslan los tokens de JavaScript del propio origen: un XSS puede robarlos. Para producción, preferir un **BFF con cookie `HttpOnly` + `Secure` + `SameSite`** para el refresh token (esta app ya tiene BFF `/ssr-api`). Si se mantiene el token en storage, asumir el riesgo y reforzar CSP + sanitización; nunca presentar `sessionStorage` como frontera de seguridad.
- **`sessionSignal(ns)`** reactivo por namespace: `login()`/`logout()` lo actualizan → el UI se desloguea solo cuando el interceptor fuerza logout.
- **authInterceptor**: extrae ns de la URL, añade `Authorization: Bearer`, hace refresh+retry en 401. Si el refresh falla → `logout(ns)` (limpia sesión + signal).
- **Client ID por app**: el BFF expone el mapa y el AuthService lo cachea; lanza error claro si no está configurado.

## [SSR] — No escribir signals en el constructor

- **Nunca escribir signals en el constructor** (NG0950, prohibido en SSR): usar `effect()` con lectura de signals.
