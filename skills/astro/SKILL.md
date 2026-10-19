---
name: astro
description: "Patrón senior para sitios Astro 7 (SSR) con Tailwind y DaisyUI y despliegue en Vercel. Usar al crear, modificar o revisar un proyecto Astro: rutas, SSR, proxy al backend, auth con Google OAuth, formularios o componentes. NO para SPA Angular ('angular'), diseño/mockups ('ui-ux-mockup') ni backend ('dotnet'/'fastapi')."
---

# SKILL: Frontend Astro — Patrón Senior (transversal)

Guía de referencia para construir aplicaciones web con **Astro 7 (SSR) + Tailwind 4 + DaisyUI 5**, siguiendo una arquitectura y convenciones senior validadas en producción. Es **transversal**: los ejemplos son genéricos (catálogos, detalle, auth Google, formularios, progreso CSR) y aplican a cualquier dominio — catálogos, blogs, SaaS, contenido, lo que sea.

Este archivo es un **skill**: se lee para replicar el patrón en cualquier proyecto Astro nuevo. No es una receta dogmática, es la lista de decisiones que convierten un sitio con SSR en una app mantenible.

**Servicios externos (todos opcionales según el proyeto, y por eso se configuran como tal):**
- **Auth**: Google OAuth (login popup con `google.accounts.oauth2`) + JWT + refresh token en cookie HttpOnly del BFF — reemplazable por cualquier proveedor OAuth.
- **API**: cualquier backend REST autenticado con `X-API-Key` (origen) + Bearer JWT (usuario) — accedido únicamente vía proxy SSR.
- **Hosting**: Vercel (adapter `@astrojs/vercel`, `output: 'server'`) — el patrón SSR aplica a cualquier host Node.

**Referencias** (se leen bajo demanda, rutas relativas a esta skill): `references/bff-proxy.md` (proxy universal + BFF de cookies auth), `references/auth-cliente.md` (auth decay-aware, `apiFetch`, `auth-ui`), `references/toast.md` (bridge SSR + store CSR).

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| SPA Angular (app de administración, signals) | `angular` |
| Diseño visual / mockups previos a implementar | `ui-ux-mockup` |
| Backend de la API | `dotnet` / `fastapi` |

El **cómo** se construye el sitio Astro (SSR, proxy BFF, auth Google, `Result<T>`) vive aquí.

> **Frescura (verificado 2026-10-13):** Astro **7.3** (2026-09-03; última 7.3.8 el 2026-10-08), Tailwind **4** y DaisyUI **5**. Fuente: astro.build/blog.

---

## 1. ¿Por qué este patrón es SENIOR?

Porque resuelve los problemas que matan a los proyectos Astro cuando crecen, con decisiones **justificadas**, no por moda:

| Decisión | Problema que resuelve |
|----------|----------------------|
| **SSR con backend real detrás** | Si el SEO y la carga inicial importan, `output: 'static'` no alcanza: el contenido se renderiza en el servidor con datos frescos |
| **Proxy universal en `pages/api/proxy/[...path].ts`** | El frontend **nunca ve** `API_URL`/`API_KEY` (quedan solo en el servidor). Un solo endpoint traduce todo el tráfico de forma transparente |
| **BFF de cookies HttpOnly** (`gg_refresh`) | El `refresh_token` no vive en `localStorage` (invisible para XSS): lo guarda el proxy en cookie `HttpOnly; Secure`, y el navegador nunca lo toca en JS |
| **`apiFetch()` con 401 → refresh + retry (una vez)** | El cliente no conoce los detalles del refresh; ante expiración rota en silencio y reintenta, y solo hace logout si el refresh falla |
| **Sesión decay-aware** (`isTokenExpired` decodifica `exp`) | La presencia de un token no alcanza: si expiró, se considera no autenticado y se refresca al boot |
| **Lógica del navegador aislada en `lib/`** | Sin `fetch`, sin `import.meta.env` en `lib/` — solo DOM/localStorage. `auth.ts`, `auth-ui.ts`, `toastTrigger.ts` son puro cliente |
| **`services/` solo SSR + `Result<T>`** | Los llamados al backend se tipan y devuelven `[data, error]`; el error llega visible al SSR sin perderse |
| **Tipos centralizados en `types/`** | Un solo `types/*.ts` fuente única; los componentes consumen la interfaz, no la duplican |
| **CSS custom SOLO en `assets/app.css`** | Prohibido `<style>` en componentes. El CSS global (glow, shimmer, swiper, scrollbar) vive en un solo archivo; todo lo demás son utility classes |
| **Assets importados con `.src`** | `import img from '@/assets/...'` devuelve `ImageMetadata` — las URLs se hashean y cachean; nunca rutas hardcodeadas tipo `/images/x.png` |
| **Toast con bridge SSR + store CSR** | `showToast()` no puede correr en SSR; el contenedor recibe el mensaje del servidor vía `[data-ssr-toast]` y lo muestra en el navegador |
| **Contenido SSR vs estado CSR** | El contenido (SEO) va por SSR en el detalle; el estado autenticado del usuario (progreso, chequear) va por CSR con el Bearer del localStorage |
| **`astro check` en CI (0 errors/0 warnings)** | Typecheck real de todos los archivos `.astro` — imposible de leer el estado del proyecto sin esto |
| **Fade navigation + bfcache restore** | Navegación entre páginas sin recarga brusca, sin romper Swiper ni perder el scroll al volver |

---

## 2. Stack

| Capa | Tecnología |
|------|-----------|
| Framework | Astro 7 (SSR, `output: 'server'`) |
| Adaptor | `@astrojs/vercel` (o cualquier nodo — el patrón es el mismo) |
| Estilos | Tailwind 4 (`bg-linear-*`, `aspect-4/5`) + DaisyUI 5 (`bg-base-100`, `text-base-content`) |
| Animaciones | `tailwind-animations` (`animate-fade-in/out`, `animate-duration-*`) |
| Typecheck | `astro check` (`pnpm check`) + `@astrojs/check` + `typescript@~6.0.0` |
| Carousels | Swiper 14+ (módulos Navigation/Pagination/Autoplay) |
| Auth | Google OAuth (popup) + JWT + refresh en cookie HttpOnly del BFF |
| Hosting | Vercel (SSR Functions) |

> ⚠️ **TypeScript 7.x NO funciona con `astro check`** (el compilador nativo no expone la API programática). Usar `typescript@~6.0.0`.

---

## 3. Estructura de carpetas (plantilla)

```text
frontend/
├── astro.config.mjs        → output: 'server', adapter vercel, alias @/* → src/*
├── package.json            → scripts: build/dev/preview/check
├── tsconfig.json           → extends astro/tsconfigs/strict, paths @/* → ./src/*
├── public/                 → SOLO archivos estáticos servidos crudos (favicon, robots). Nunca assets de la app
└── src/
    ├── assets/
    │   ├── app.css         → Tailwind 4 + DaisyUI + CSS global (glow, shimmer, swiper, scrollbar, themes)
    │   └── images/         → SOLO assets importados desde el código (logo, google, fallback)
    ├── layouts/
    │   └── Layout.astro    → <html>, Navbar, Footer, ModalImage, ToastContainer
    ├── lib/                → SOLO cliente (DOM, localStorage permitidos; sin fetch, sin import.meta.env)
    │   ├── auth.ts         → tokens, sesión decay-aware, login, logout, refresh, apiFetch
    │   ├── auth-ui.ts      → initAuthUI(elements): centraliza updateUI/login/logout, listener authchange único
    │   └── toastTrigger.ts → store de toasts (showToast/subscribeToasts/dismissToast + toastStyles)
    ├── services/           → SOLO SSR (frontmatter). Devuelven Result<T>, llaman al proxy
    │   └── games.ts        → getGames() → Result<GameListResult>, getGameBySlug() → Result<GameDetail>
    ├── types/
    │   ├── game.ts         → modelos fuente única (Game, GameDetail, Platform, Genre, ...)
    │   ├── progress.ts     → DTOs CSR del estado del usuario
    │   └── result.ts       → Result<T> = [data, error | null]
    ├── pages/
    │   ├── index.astro     → home: secciones SSR
    │   ├── list.astro      → catálogo paginado
    │   ├── detail/[slug].astro → detalle SSR (1 llamada al backend)
    │   └── api/proxy/[...path].ts → PROXY UNIVERSAL (único punto de salida al backend)
    └── components/
        ├── Navbar/         → agrupados por feature: Navbar, NavLinks, NavThemeToggle, AuthGoogle
        ├── Hero/           → Hero, HeroHeader, ...
        ├── GameSlider/     → slider + card
        ├── FeaturedGames/  → FeaturedGames, FeaturedGameCard
        ├── ModalImage.astro → <dialog> nativo, activado por data-modal (una vez en Layout)
        ├── toastContainer.astro → bridge SSR [data-ssr-toast] + contenedor CSR
        ├── Stars.astro     → rating
        ├── TagPill.astro
        └── Loading.astro
```

**Regla**: los componentes se agrupan por **feature en carpetas** (`Navbar/`, `Hero/`, `GameSlider/`). Un componente se importa con `import X from '@/components/Feature/X.astro'`.

---

## 4. Convenciones de capas

### 4.1 `lib/` — solo lógica del navegador
- Sin `fetch` directo (excepto el wrappero), sin `import.meta.env` (excepto `PUBLIC_*`), sin SSR.
- `auth.ts` es la única fuente de autenticación; el resto del código consulta `isAuthenticated()`, `getUser()`, `apiFetch()`.

```ts
// src/lib/auth.ts
export function isAuthenticated(): boolean {
  const token = getAccessToken();
  return !!token && !isTokenExpired(token); // decay-aware: presencia + exp válido
}

export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  // 401 → refresh silencioso → retry UNA vez → si falla, logout()
}
```

### 4.2 `services/` — solo SSR (frontmatter)
- Llaman al proxy (`/api/proxy/...`) y devuelven `Result<T> = [data, error]`.
- Se usan en el frontmatter `--- ---` de páginas y componentes SSR.

```ts
// src/services/games.ts
export async function getGameBySlug(slug: string, origin: string): Promise<Result<GameDetail>> {
  try {
    const res = await fetch(`${origin}/api/proxy/games/by-slug/${slug}/detail`);
    if (!res.ok) return [null, `Error ${res.status}`];
    return [await res.json(), null];
  } catch (e) {
    return [null, 'Error de red'];
  }
}
```

### 4.3 `types/` — fuente única
- Un solo archivo por dominio (`game.ts`, `progress.ts`). **Nunca** duplicar interfaces en los componentes.
- `Result<T> = [data, error | null]` para los servicios.

### 4.4 Componentes — solo clases utilitarias
- Todo con utility classes de Tailwind/DaisyUI: `bg-base-100`, `text-base-content`, `from-primary`, `border-error/10`.
- **Prohibido `<style>`** con reglas CSS en componentes. El único CSS global vive en `assets/app.css`.
- Excepción: `style="..."` inline solo para **fondo dinámico** (`background-image: url(${img.src})`) o **backdrop fijo** de navbar/footer (casos no cubribles con utilities dinámicas).
- Tailwind 4: **`bg-linear-*` no `bg-gradient-*`**, `aspect-4/5` nativo, `backdrop-blur-*`.

---

## 5. Proxy universal BFF (`pages/api/proxy/[...path].ts`)

El corazón del patrón: **una sola ruta** que traduce toda la comunicación con el backend. **Reglas de oro**: único lugar que lee `API_URL`/`API_KEY`; `buildHeaders()` agrega `X-API-Key` y reenvía el `Authorization` entrante (el front solo manda el Bear); **sin try/catch que trague el status**; GET sin body y 204 sin body. El BFF guarda el `refresh_token` en cookie `HttpOnly` (nunca en `localStorage`).

**Referencia**: código del proxy y del BFF de cookies en `references/bff-proxy.md`.

---

## 6. Auth cliente — decay-aware + refresh + retry

- Solo `access_token` + `user` en `localStorage` (el refresh vive en la cookie del BFF, no en el navegador).
- `isTokenExpired(token)` decodifica `exp`: al boot, `clearExpiredSession()` refresca en silencio y solo hace `logout()` si el refresh falla.
- `apiFetch()`: 401 → refresh+retry **una vez** → si falla, `logout()`; `logout()` dispara `authchange` para que la UI se re-sincronice sola.
- **`auth-ui.ts`**: `initAuthUI(elements)` registra el listener `authchange` **una sola vez** (el bug clásico es acumularlo dentro del click de logout). Un `<script is:inline>` previo solo hace FOUC-prevention.

**Referencia**: código de `lib/auth.ts` y `lib/auth-ui.ts` en `references/auth-cliente.md`.

---

## 7. Toast — bridge SSR + store CSR

`lib/toastTrigger.ts` es un store **solo cliente** (`showToast()` no corre en SSR). El contenedor tiene dos formas: con props `message?`/`type?` renderiza un `<div data-ssr-toast>` (bridge que deja el mensaje en el HTML del servidor); sin props es el contenedor CSR apilable (montado una vez en Layout) que se suscribe al store y procesa los bridges. **Nota**: usa `<section>` con clases propias, **no** `toast toast-end` de DaisyUI.

**Referencia**: el store y el contenedor están en `references/toast.md`.

---

## 8. Assets — siempre importados con `.src`

En Astro, `import img from '@/assets/images/x.png'` devuelve un objeto `ImageMetadata` (`{ src, width, height }`), **no** un string.

```astro
---
import fallback from '@/assets/images/mewtwo.png';
---
<img src={fallback.src} alt="" />  <!-- ✅ .src → URL hasheada con cache-busting -->
```

`url("${fallback}")` (sin `.src`) rompe a `url([object Object])` y la imagen nunca carga. **Regla**: rutas hardcodeadas tipo `/images/x.png` ni interpolar el objeto. `public/` queda solo para favicon/robots; los assets de la app van en `src/assets/` y se importan.

---

## 9. Contenido SSR vs estado CSR (el detalle)

- **Contenido** (SEO): va por **SSR** en el detalle enriquecido — una sola llamada a `/by-slug/{slug}/detail` desde el frontmatter.
- **Estado del usuario autenticado** (progreso, checks): va por **CSR**, porque el JWT vive en `localStorage` y el SSR nunca lo ve.
- El cliente hace `fetch('/api/proxy/...')` con `Authorization: Bearer <token>`; el proxy agrega `X-API-Key` y reenvía el Bear.
- GET define el estado inicial; la interacción es solo POST/DELETE. Errores: red → toast "Error de red"; 401 → `apiFetch` refresca+reintenta (si falla, logout → UI se re-sincroniza sola).

```ts
// Patrón de progreso CSR genérico
async function fetchProgress<T>(path: string, method: string, body?: unknown): Promise<T | null> {
  // red caída → toast; 401 → apiFetch maneja refresh+retry/logout; 204 → {} as T
}
```

---

## 10. Navegación — fade + bfcache

- Las cards/navegación interna no recargan duro: fade-out + cambio de URL + fade-in.
- El restore al volver atrás/adelante (bfcache) requiere un `pageshow` con `e.persisted` que remueve `animate-fade-out` y re-aplica `animate-fade-in` (si no, el `<main>` queda en `opacity: 0`).
- Cards responsivas en flex: `min-w-0` + `truncate`.

---

## 11. Checklist final (¿esto es SENIOR?)

Antes de dar una app Astro por terminada:

- [ ] SSR con backend real (`output: 'server'`) y `pnpm build` OK
- [ ] Proxy universal único (`pages/api/proxy/[...path].ts`) — API_URL/API_KEY solo en el servidor; status codes intactos
- [ ] BFF de cookies: refresh_token en cookie HttpOnly (nunca en localStorage); `/auth/google|refresh|logout` especiales
- [ ] `apiFetch()` con Bear → 401 → refresh+retry (1 vez) → logout si falla
- [ ] Sesión decay-aware (`isTokenExpired` sobre `exp` del JWT) + `clearExpiredSession()` al boot
- [ ] `lib/` solo cliente (DOM/localStorage; sin fetch excepto apiFetch, sin import.meta.env excepto PUBLIC_*)
- [ ] `services/` solo SSR + `Result<T>`; `types/` fuente única (sin interfaces duplicadas)
- [ ] CSS solo en `assets/app.css`; cero `<style>` en componentes; `bg-linear-*`; excepciones solo fondo dinámico/backdrop
- [ ] Assets importados siempre con `.src` (ImageMetadata); sin rutas hardcodeadas; `public/` solo estáticos
- [ ] Toast con bridge SSR (`data-ssr-toast`) + store CSR único montado en Layout
- [ ] `astro check` (0 errors/0 warnings/0 hints) + `@astrojs/check` + TS ~6.0.0 en devDeps
- [ ] Auth UI centralizada en `lib/auth-ui.ts` (un solo listener `authchange`, sin leaks); `is:inline` solo FOUC-prevention
- [ ] Navegación interna con fade + restore bfcache (`pageshow` con `e.persisted`)
- [ ] ModalImage como `<dialog>` nativo activado por `data-modal`, renderizado una vez en Layout
- [ ] `npm` prohibido → `pnpm` (build/dev/preview/check)

---

## 12. Errores comunes (anti-patrones)

| Anti-patrón | Por qué evitarlo |
|-------------|------------------|
| `import img from '...'` y usar el objeto en `url("${img}")` | Es `ImageMetadata` → sale `[object Object]` y la imagen no carga. Usar siempre `.src` |
| Rutas hardcodeadas `/images/x.png` en el código | No se hashean ni cachean; se rompen con el build/deploy. Importar desde `src/assets/` |
| `<style>` en componentes (is:inline/is:global) | Fragmenta el CSS; los cambios se pierden entre archivos. Todo global va en `app.css` |
| `bg-gradient-*` en Tailwind 4 | Fue renombrado a `bg-linear-*`; `bg-gradient-*` no genera el estilo |
| `fetch()` directo con `API_URL`/`API_KEY` en el navegador | Expone secretos. Siempre por el proxy univers |
| Refresh token en `localStorage` | Vulnerable a XSS. Cookie HttpOnly del BFF |
| Listener de `authchange` registrado dentro del click de logout | Acumula listeners duplicados (leak). Registrarlo una sola vez en `initAuthUI` |
| Confiar en la presencia del token sin chequear `exp` | Un token expirado se trata como autenticado; el fetch va a fallar feo. `isTokenExpired` |
| Tratar el 401 solo como error | Perder la foto del usuario; el flujo correcto es refresh+retry vía `apiFetch` |
| Un fetch SSR genérico sin `Result<T>` | El error se pierde; con `[data, error]` el SSR muestra el error visiblemente |
| `.env` con `API_URL`/`API_KEY` expuesto al cliente | Si algo lo filtra vía `import.meta.env` (no `PUBLIC_`), es una filtración. Solo el proxy lo lee |
| Test-check sin `astro check` | Sin typecheck real de `.astro` el refactor es a ciegas. `pnpm check` 0 errors en CI |
| Vídeo/Swiper `is:global` en el componente | Mover los estilos de swiper/paginación a `app.css` scoped por clase contenedora (`.featuredSwiper`) |
| Verificar `isLoading()` solo, sin `hasValue()` en listas CSR | Pierde el estado abierto/expansión al refetchear. Usar `isLoading() && !hasValue()` |