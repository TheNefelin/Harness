# SSR y build

> Detalle de la sección **SSR y build** de la skill `angular`. Aplica **solo** si usas SSR; en CSR no existe `server.ts` ni proxy.

- `src/server.ts`: Express + proxy `/ssr-api/{namespace}/{path}` + handlers multipart (`req.is('multipart/form-data')` para validar el upload).
- `app.routes.server.ts`: `RenderMode` por página. Dashboards de admin → `RenderMode.Client` (sin prerender, la API disponible al renderizar en el navegador).
- **Build de producción**: `ng build` (genera `dist/.../server/server.mjs`); `npm start` debe apuntar al **servidor Express de producción** (`node dist/.../server/server.mjs`), **nunca** a `ng serve` (dev server sin SSR).
- **Verificación**: `ng build` valida plantillas + `pnpm lint` (0 errores) — ambos antes de declarar una feature terminada.
