---
name: angular
description: Patrón senior para aplicaciones Angular signal-based con Tailwind y DaisyUI (CSR y SSR). Usar cuando se cree, modifique o revise código Angular: componentes, servicios, rxResource, CrudPage, MutationService, formularios, auth, interceptores o lint con angular-eslint.
---

# SKILL: Angular — Patrón Senior (transversal: CSR y SSR)

Guía de referencia para construir aplicaciones web con **Angular (Signal-based) + Tailwind + DaisyUI**, siguiendo una arquitectura y convenciones senior validadas en producción. Este skill es **transversal**: aplica tanto a **CSR** (SPA clásica) como a **SSR** (con Express), y los ejemplos son genéricos (CRUD de administración, listados paginados, formularios, uploads, auth). No es una receta dogmática, es la lista de decisiones que convierten un CRUD simple en un admin mantenible.

> **Cómo leer este documento:** hay dos modos de ejecución. La mayoría de las reglas aplican a **ambos**. Cuando una regla es específica de un modo, se marca con **[CSR]** o **[SSR]**.
>
> - **[CSR]**: SPA pura. La API se consume directo (URL base desde `environment.apiUrl`). Sin `server.ts`, sin proxy.
> - **[SSR]**: con Express (`src/server.ts`) y proxy `/ssr-api/...`; las credenciales de la API quedan solo en el servidor.

---

## 1. ¿Por qué este patrón es SENIOR?

Porque resuelve los problemas que matan a las apps Angular cuando crecen, con decisiones **justificadas**, no por moda:

| Decisión | Problema que resuelve |
|----------|----------------------|
| **[SSR] SSR con Express (`src/server.ts`)** | La app admin carga con la API disponible y no con HTML vacío; el render de las rutas se controla con `RenderMode` por página (`Client` para dashboards sin prerender) |
| **[SSR] Proxy SSR `/ssr-api/[...]` + handlers multipart** | El frontend **nunca ve** credenciales de la API (quedan solo en el servidor). Un solo punto traduce todo el tráfico, incluido el upload de imágenes con `form-data` |
| **Señales + `rxResource` para lecturas** | Estado reactivo declarativo, sin `subscribe()` manual en componentes; los GETs exponen `isLoading()`/`hasValue()`/`error()` |
| **`MutationService` para mutaciones** | Un único patrón de create/update/delete/upload: `isSaving` + toast de éxito + `console.error` + callback `onClose` que corre SOLO en éxito (si falla, el modal queda abierto con los datos intactos) |
| **`output()` con nombres sin prefijo `on`** | La regla `no-output-on-prefix` de Angular ESLint: los outputs se nombran `submit`/`closed`/`delete`, no `onSubmit`/`onClose`/`onDelete` — evita confusión con listeners DOM |
| **`CrudPage<TModel>` (clase base abstracta)** | Todo listado paginado comparte señales (`totalPages`/`currentPage`/`limit`/`search`) y métodos (`nextPage`/`prevPage`/`onFilterChange`/`onRefreshClick`); la subclase solo implementa `reload()` |
| **Paginación unificada** | `PaginationRequestModel` (`page`, `limit`, `search`, `filter?`) para todos los GET paginados; `limit` acotado (máx. 100) acorde a la API; `filter` tipado por feature |
| **`linkedSignal` + `clearTrigger` en formularios** | El form data reacciona al payload (edit mode) y se resetea a valores por defecto incrementando un trigger — sin `patchValue` manual ni estado zombie |
| **Auth por namespace** | Sesión en `sessionStorage` con prefijo `auth.{namespace}.access_token/refresh_token/user`; el interceptor añade el Bearer según el namespace, hace refresh+retry en 401 y fuerza logout si el refresh falla |
| **Auth con `sessionSignal(ns)` reactivo** | El estado de login es una signal por namespace: al forzar logout la UI se re-sincroniza sola, sin recargar |
| **`ErrorService` (modal) + `SuccessService` (toast) + `ConfirmService` (promise-based)** | Feedback de usuario centralizado: errores HTTP en modal vía interceptor (única fuente), éxitos en cola de toasts con auto-cierre, confirmaciones con `await confirm()` que resuelve `boolean` |
| **ESLint con `angular-eslint`** | Lint de TS + templates (accesibilidad incluida) en `pnpm lint`, 0 errores — el refactor deja de ser a ciegas |
| **Spinner solo en carga inicial** | `isLoading() && !hasValue()` en vez de `isLoading()`: al refetchear la lista no se desmonta (acordeón/expansión conserva su estado) |
| **`(ngSubmit)` en lugar de `(submit)`** | `NgForm.onSubmit` devuelve `false` en forms normales y Angular llama `preventDefault()` automáticamente — Enter no recarga la página. **⚠️ IMPORTANTE**: `(ngSubmit)` es un evento del directive `NgForm`; sin **`FormsModule` importado** en el componente **nunca dispara** y el form hace submit nativo (recarga GET). Ver §7 Forms |
| **Formularios con validación local** | Dos variantes senior: (a) `<form (ngSubmit)>` con `FormsModule` importado, o (b) `<form>` **sin** evento de submit + botón `type="button"` con `(clicked)="onSaveClick()"` — la variante (b) es la convención dominante en los modales CRUD (genre/author/subject/editorial/format/copy). Las validaciones se muestran con un componente de mensaje local, nunca como toast/modal |

---

## 2. Stack

| Capa | Tecnología (CSR) | Tecnología (SSR) |
|------|------------------|------------------|
| Framework | Angular 22, Signal-based | Angular 22, Signal-based |
| Bundling | Angular CLI + `pnpm` | Angular CLI + `pnpm` |
| Ejecución | **SPA** (browser) | Express (`src/server.ts`) |
| Estilos | Tailwind 4 + DaisyUI 5 | Tailwind 4 + DaisyUI 5 |
| Estado | Signals (`linkedSignal`, `clearTrigger`, `sessionSignal`) | Idem |
| Data fetching | `rxResource` (lecturas) + `MutationService` (mutaciones) | Idem |
| Acceso a API | Directo desde `environment.apiUrl` **[CSR]** | Vía proxy `/ssr-api/...` **[SSR]** |
| Lint | ESLint 10 (flat config, `angular-eslint`) | Idem |
| Typecheck | `ng build` (valida plantillas) + `strict: true` | Idem |

> ⚠️ **TypeScript**: el proyecto usa `typescript@~6.0.0`. Verificar la versión compatible con la de Angular antes de instalar.

---

## 3. Estructura de carpetas (plantilla)

```
admin/
├── src/server.ts                  → [SSR] Express SSR + proxy /ssr-api/ + handlers multipart (solo SSR)
├── eslint.config.js               → flat config: angular-eslint tsRecommended + templateRecommended + templateAccessibility; ignores dist/
└── src/app/
    ├── core/
    │   ├── services/
    │   │   ├── api-service.ts     → CRUD genérico + postWithFile<T>() multipart + deleteResource<T>()
    │   │   ├── auth-service.ts    → login OAuth, refresh (rotación), logout; sesión por namespace; sessionSignal(ns)
    │   │   ├── error-service.ts   → Error signal global (modal)
    │   │   ├── success-service.ts → cola de toasts con auto-cierre y cierre manual
    │   │   ├── confirm-service.ts → diálogo promise-based (dialog signal + confirm()/accept()/reject())
    │   │   └── mutation-service.ts → patrón único de mutaciones (isSaving + toast + onClose en éxito)
    │   └── interceptors/
    │       ├── auth-interceptor.ts    → [CSR] Bearer de localStorage/sessionStorage; [SSR] del namespace; refresh+retry en 401
    │       └── error-interceptor.ts   → formatea el detail del backend a la error signal (única fuente)
    ├── shared/
    │   ├── base/
    │   │   └── crud-page.ts       → CrudPage<TModel>: paginación/filtro/reload abstracto
    │   ├── components/            → button, loading, image-picker, image-viewer, modal-confirm, pagination-filter, select-list, select-search, toast-success, ...
    │   ├── models/                → pagination, select-item, ...
    │   └── constants/
    │       └── routes-constant.ts → rutas
    └── features/
        └── {domain}/
            ├── {feature}/
            │   ├── models/        → Model + SaveModel (fuente única, nunca duplicar)
            │   ├── services/      → CRUD + uploads
            │   ├── pages/         → {feature}-page/ (lista paginada) + {feature}-form-page/ (form complejo)
            │   └── components/    → {feature}-form-component/ (modal), {feature}-list-component/ (tabla/grid),
            │                       {feature}-select-component/ (select con búsqueda),
            │                       {feature}-selected-list-component/ (lista de seleccionados con delete)
            └── {feature}.routes.ts
```

**Regla**: un feature CRUD = `models/` + `services/` + `pages/` + `components/`. Los componentes se agrupan por feature, nunca en un `components/` global con todo. **Nomenclatura singular**: todos los componentes usan `-component` (sin `s`), tanto en nombre de archivo como de clase y selector (`app-x-component`).

**Convención de nombres en pages**: el servicio inyectado se nombra `<feature>Service` (p. ej. `editorialService`, `genreService`) y el rxResource `getAll<Feature>RX` (p. ej. `getAllEditorialRX`). Nunca `service` genérico ni `getAllRX`.

**Diferencia clave de modo:**
- **[CSR]**: no hay `src/server.ts`; la API se consume desde `environment.apiUrl`. La sesión vive en `localStorage`/`sessionStorage` del navegador.
- **[SSR]**: hay `src/server.ts` con el proxy; la API se consume vía `/ssr-api/...`; el navegador nunca ve las credenciales de la API.

---

## 4. Convenciones de capas

### 4.1 Servicios — todos pasan por un servicio base / `ApiService`

- **Nunca** `HttpClient` directo en páginas/componentes: todo pasa por un servicio base genérico (inyecta la URL de la API) o el `ApiService`.
- GET paginados devuelven el payload tipado del recurso; los `query params` (search, limit, filter) se serializan con `encodeURIComponent()` en `search`.
- Upload multipart: `postWithFile<T>()` con los form fields del recurso; delete de imagen: `deleteResource<T>()`.
- Búsquedas seguras: `search` siempre con `encodeURIComponent()` (evita romper URLs con `&`, `=`, `#`, `%`) y `!== ''`.
- **[CSR] cache en memoria**: un `BaseService` puede cachear GETs con TTL (p. ej. 5 min) e invalidar con `clearCache()` para catálogos que no cambian seguido.

### 4.2 Páginas de listado — `CrudPage<TModel>`

```ts
// shared/base/crud-page.ts (esqueleto)
export abstract class CrudPage<TModel> {
  protected readonly totalPages = signal(0);
  protected readonly currentPage = signal(1);
  protected readonly limit = signal<number>(10);
  protected readonly search = signal('');

  protected readonly getAllPayload = computed(() => ({
    page: this.currentPage(),
    limit: this.limit(),
    search: this.search(),
  }));

  nextPage(): void { ... }
  prevPage(): void { ... }
  onFilterChange(filter: { search: string; limit: number }): void { ... }
  onRefreshClick(): void { ... }
  abstract reload(): void;
}
```

- La subclase implementa `reload()` (recarga su `rxResource`) y conserva SUS GETs y mutaciones.
- **Override**: para cambiar un valor/lógica heredado usar `protected override` (requiere palabra `override` por `noImplicitOverride: true`).
- Streams `rxResource` **puros**: el side-effect de `totalPages.set()` va en helpers (`mapPaginated`/`emptyPaginated`), nunca dentro del `map` — si no, la paginación queda stale cuando una request falla.
- **Estado agrupado por feature**: el listado, loading, guardado, modal y item seleccionado se agrupan en un objeto plano con signals/computed. Nunca signals sueltas dispersas.

```ts
// patrón de estado agrupado en el page
protected readonly genre = {
  dataList:    computed<GenreModel[]>(() => this.getAllGenreRX.value() ?? []),
  isLoading:   computed<boolean>(() => this.getAllGenreRX.isLoading()),
  isSaving:    signal<boolean>(false),
  showModal:   signal<boolean>(false),
  selectedItem: signal<GenreModel | null>(null),
}
```

- **Convención de handlers**: los métodos de acción usan `on` + nombre de la acción (`onCreateGenre`, `onEditGenre`, `onDeleteGenre`, `onClearGenreForm`, `onSubmitGenreForm`). `onClear*` cierra el modal y limpia selectedItem. `onSubmit*` desestructura `{ id, data: SaveModel }` del form y delega a `MutationService`.
- **El form emite `{ id, data: SaveModel }`**: el componente form output `submitForm = output<{ id: number, data: SaveModel }>()`. El id es `0` en creación o `feature.id` en edición. El page extrae `id` y `data` y decide create vs update.

#### 4.2.1 Listado paginado con filtro por catálogo

Patrón para listados con filtro por estado/catálogo (reservation, loan y sus status):

- **`getPaginationPayload` privado por página** (computed tipado con el `*FilterModel`). No se hace `override` de `getAllPayload` de `CrudPage`: es `PaginationRequestModel<null>` y por la varianza de `Signal<PaginationRequestModel<...>>` (TS2416) un `computed<...<LoanFilterModel>>` no es asignable a `computed<...<null>>`.
- **El select del catálogo emite el modelo completo** y el page recibe el item en el handler:
  `onFilterByIdStatus(status: FeatureStatusModel | null)` → `selectFilterStatusId.set(status?.id_status ?? 0)` + `currentPage.set(1)`.
- **Sentinel `0 = todos`**: `selectFilterStatusId = signal<number>(0)`; `ApiService.buildQuery` omite números `<= 0`, así que `0` = sin filtro.
- **Stream puro del rxResource de listado**:
  ```
  if (!params) return of(null);
  return this.featureService.getAllPagination(params).pipe(
    map(response => this.mapPaginated(response)),
    catchError(err => { console.error('[Service::Page] getAllPagination:', err); return of(this.emptyPaginated()); }),
  );
  ```
  Los side-effects de `totalPages` viven solo en `mapPaginated`/`emptyPaginated`.
- **El list component es presentacional y reemite el filtro**: `selectedIdStatus = output<FeatureStatusModel | null>()`; el template hace `<app-x-status-select-component [selectedId]="selectStatusId()" (selectedItem)="selectedIdStatus.emit($event)" />`.

### 4.3 Mutaciones — `MutationService`

```ts
// core/services/mutation-service.ts (esqueleto)
run<T>(action: Observable<T>, state: { isSaving: WritableSignal<boolean> },
       options?: { successMsg?: string; errorMsg?: string; onSuccess?: () => void; onClose?: () => void; onFinalize?: () => void }): void {
  state.isSaving.set(true);
  action.pipe(finalize(() => state.isSaving.set(false))).subscribe({
    next: () => { if (succeeded) options?.onClose?.(); toast.success(...); options?.onSuccess?.(); },
    error: err => console.error(...),
  });
}
```

- **`onClose` corre SOLO en éxito**: si la API falla, el modal queda abierto con los datos intactos (el usuario no pierde lo escrito).
- Estado `isSaving` agrupado por feature (p. ej. `{ isSaving: this.genre.isSaving }`), nunca signals planos dispersos.
- **Delete con `ModalConfirmService`**: antes de borrar, `await this.confirmService.confirm({ title, message })` resuelve `boolean`. Si `false`, se aborta. La mutación de delete pasa el id del item, no el objeto.

### 4.4 Formularios — `linkedSignal`

```ts
// patrón real del form component (modal)
protected readonly formData = linkedSignal<SaveModel | null, SaveModel>({
  source: this.model,  // input() con el modelo a editar (null = creación)
  computation: (item) => item ?? { name: '' },  // defaults por campo
});

protected readonly submitForm = output<{ id: number, data: SaveModel }>();
```

- `linkedSignal` con `computation` reacciona al cambio del **source** (input del modelo). Cuando `selectedItem` se setea a `null` (cerrar modal), el source cambia y el form resetea a defaults automáticamente — sin `effect()` ni `clearTrigger` para el form data.
- `clearTrigger` se usa en **select components** (para limpiar la selección visual), no en el form principal.
- El form emite `{ id, data }`: `id = 0` en creación, `id = feature.id` en edición. El page decide create vs update.
- Validaciones **locales** con `validateFormOnSubmit()`, nunca toast/modal. Retorna `string | null` (null = válido).
- Submit con `(ngSubmit)` **solo si `FormsModule` está importado** (es el evento de `NgForm`; sin él no dispara y el form hace submit nativo). Alternativa senior: `<form>` sin evento + botón `type="button"` con `(clicked)` — la convención dominante en modales.
- Template lee fechas/ids del **input** `model()`, no de `formData()`: `<p>ID: {{ model()?.id }}</p>` (no `formData().id`).

### 4.5 Componentes — outputs y accesibilidad

- **Outputs sin prefijo `on`**: `submit`, `closed`, `delete`, `edit`, `selectedFile`, `deleteFile`, `confirm`... La regla `no-output-on-prefix` de Angular ESLint lo exige.
- **No nombrar outputs como eventos DOM nativos** (`close`, `click`, `submit`): `no-output-native` los marca. Usar `closed`/`clicked`/`submitted`.
- **Métodos handler `onXxx(...)` son correctos**: la regla aplica solo a `output()`/`@Output()`, no a métodos.
- **Labels**: usar `<label>` solo cuando hay un control asociado (`for` + `id`, o asociación implícita envolviendo el input). Encabezados de sección → `span`; contenedores sin control → `div` (`label-has-associated-control`).
- **Interactivos**: elementos clickeables no nativos necesitan `role="button"` + `tabindex="0"` + handler de teclado (`keydown.enter/space`) (`interactive-supports-focus`, `click-events-have-key-events`).
- **Spinner de carga**: `isLoading() && !hasValue()` para no desmontar la lista en refetch.

#### 4.5.1 `ChangeDetectionStrategy.OnPush` en todos los componentes

- **Todos los componentes con selector `app-*` usan `changeDetection: ChangeDetectionStrategy.OnPush`**. No es exclusivo de zoneless: es la estrategia recomendada por Angular para apps con signals.
- **Signals + OnPush = máximo rendimiento**: al re-renderizar solo se revisan los componentes que leen un signal que cambió; los presentacionales (input/output) se marcan y saltean su subárbol.
- **En Angular 21+ (zoneless por defecto) OnPush no es estrictamente requerido**, pero sigue siendo **recomendado** para los componentes de la aplicación. La documentación oficial lo explicita (guía "Angular without ZoneJS (Zoneless)" → sección "OnPush-compatible components").
- **Dependiendo de la versión de Angular, consultar la documentación oficial** antes de asumir el comportamiento de detección de cambios: `https://angular.dev/guide/zoneless` (y `https://angular.dev/best-practices/skipping-subtrees` para la semántica de OnPush).
- **Excepción (no usar OnPush a ciegas)**: componentes que mutan estado en callbacks no reactive (timers, `Date.now()` en template, `subscribe()` manual) y no notifican a Angular; en esos casos el render puede congelarse. Si el componente fue migrado a signals puede adoptar OnPush sin riesgo.
- **Import**: `ChangeDetectionStrategy` desde `@angular/core` (no desde otra ruta).

### 4.6 Select components, selected-list y resolución de modelos

**Select component** (`{feature}-select-component/`):
- Emite el modelo completo via `selectedItem = output<FeatureModel | null>()` (el item seleccionado, `null` al limpiar).
- Contiene su propio `rxResource` para cargar la lista de opciones (`getAll()`).
- Expone `clearTrigger = input<number>(0)` para resetear la selección visual desde el padre.
- Expone `selectedId = input<number | undefined>(undefined)` (sin default numérico) para preseleccionar desde el padre.
- Emitir el modelo completo evita que el consumidor haga un segundo fetch del catálogo para resolver id → modelo.

**Selected-list component** (`{feature}-selected-list-component/`):
- Recibe la lista de items seleccionados como `input<FeatureModel[]>([])` (con default vacío).
- Emite `delete = output<FeatureModel>()` (sin prefijo `on`).
- El handler interno `handleDelete` hace `event.preventDefault()` + `event.stopPropagation()` antes de emitir.

**Consumo del modelo en el consumidor** (`book-form-component`, `edition-form-components`):
- El select emite el `FeatureModel` completo; el consumidor lo agrega directamente a su lista de seleccionados (sin re-fetch):

```ts
// book-form-component: recibe el AuthorModel completo del select
protected addAuthor(item: AuthorModel | null): void {
  if (!item) return;
  this.formData.update(data => ({
    ...data,
    authors: [...(data.authors ?? []), item]
  }));
}
```

- El `delete` del selected-list delega al page (`onDeleteAuthor`/`onDeleteSubject`) que solo persiste en modo edición (`isEditMode()`). En creación solo actualiza `formData` local (no hay filas puente en BD aún).

---

## 5. Auth

El patrón de auth difiere según el modo.

### 5.1 [CSR] — Auth directo

- La API se consume directo desde `environment.apiUrl`; el `authInterceptor` añade `Authorization: Bearer <token>`.
- El token se guarda en el navegador (`localStorage` o `sessionStorage` según la app; `localStorage` sobrevive al cierre de pestaña).
- `authInterceptor` (funcional, `HttpInterceptorFn`): lee el token y clona el request con el header.
- Guardo simple: no hay multi-tenant ni proxy.

### 5.2 [SSR] — Auth multi-tenant (por namespace)

```
GET /ssr-api/config                    → { googleClientIds } (mapa por namespace)
POST /ssr-api/{namespace}/auth/google  → login con el client ID de ese namespace
GET/POST/DELETE /ssr-api/{namespace}/{resource}  → CRUD con Bearer del namespace
```

- **Sesión**: `sessionStorage` con prefijo `auth.{namespace}.access_token/refresh_token/user` — sobrevive a F5, muere al cerrar la pestaña.
- **`sessionSignal(ns)`** reactivo por namespace: `login()`/`logout()` lo actualizan → el UI se desloguea solo cuando el interceptor fuerza logout.
- **authInterceptor**: extrae ns de la URL, añade `Authorization: Bearer`, hace refresh+retry en 401. Si el refresh falla → `logout(ns)` (limpia sesión + signal).
- **Client ID por app**: el BFF expone el mapa y el AuthService lo cachea; lanza error claro si no está configurado.

### 5.3 [SSR] — No escribir signals en el constructor

- **Nunca escribir signals en el constructor** (NG0950, prohibido en SSR): usar `effect()` con lectura de signals.

---

## 6. Feedback de usuario (Error/Success/Confirm)

- **Error → `ErrorService`** (modal): `errorService.show(msg)` setea una signal única; los layouts renderizan el modal. El `errorInterceptor` lo dispara automáticamente ante cualquier HTTP error (única fuente; las páginas no llaman `errorService.show`).
- **Éxito → `SuccessService`** (toast): `show(msg)` acumula en cola (`ToastModel[]`), auto-cierre a los 5s + cierre manual. Solo en operaciones de escritura.
- **Confirmación → `ConfirmService`** (promise-based): `await confirmService.confirm({ title, message })` resuelve `boolean`. La página **nunca** toca los outputs del modal (`confirm`/`closed`), solo espera el boolean.
- **Validaciones de formulario** → componente local de mensaje, nunca toast/modal.
- **Mensajes de error reales**: `err?.error?.detail || err?.message || fallback` — el interceptor ya formatea, no sobrescribir con genéricos.

---

## 7. [SSR] SSR y build

> Sección que aplica **solo** si usas SSR. En CSR no existe `server.ts` ni proxy.

- `src/server.ts`: Express + proxy `/ssr-api/{namespace}/{path}` + handlers multipart (`req.is('multipart/form-data')` para validar el upload).
- `app.routes.server.ts`: `RenderMode` por página. Dashboards de admin → `RenderMode.Client` (sin prerender, la API disponible al renderizar en el navegador).
- **Build de producción**: `ng build` (genera `dist/.../server/server.mjs`); `npm start` debe apuntar al **servidor Express de producción** (`node dist/.../server/server.mjs`), **nunca** a `ng serve` (dev server sin SSR).
- **Verificación**: `ng build` valida plantillas + `pnpm lint` (0 errores) — ambos antes de declarar una feature terminada.

---

## 8. Checklist final (¿esto es SENIOR?)

Antes de dar una app Angular por terminada:

- [ ] `ng build` (0 errores, valida plantillas) + `pnpm lint` (0 errores)
- [ ] **Modo consistente**: el proyecto es CSR o SSR; si es CSR, sin `server.ts`; si es SSR, `npm start` = `node dist/.../server.mjs` (no `ng serve`)
- [ ] **[SSR]** Proxy `/ssr-api/...` + handlers multipart validados con `req.is('multipart/form-data')`
- [ ] Signals + `rxResource` para lecturas; sin `subscribe()` manual en componentes de listado
- [ ] `ChangeDetectionStrategy.OnPush` en todos los componentes (señales + OnPush = máximo rendimiento); comportamiento verificado contra la doc oficial según la versión de Angular
- [ ] `MutationService` con `onClose` solo en éxito (el modal no pierde datos al fallar)
- [ ] Outputs sin prefijo `on` y sin nombres de eventos DOM nativos (`no-output-on-prefix`, `no-output-native`)
- [ ] `CrudPage<TModel>` para listados paginados; streams `rxResource` puros (`mapPaginated`/`emptyPaginated`)
- [ ] Filtro por catálogo: `getPaginationPayload` privado por página + handler `onFilterByIdStatus(Model | null)` con sentinel `0 = todos`
- [ ] Estado agrupado por feature (`{ dataList, isLoading, isSaving, showModal, selectedItem }`); handlers `onCreate*`/`onEdit*`/`onDelete*`/`onClear*`/`onSubmit*`
- [ ] `linkedSignal` con `computation` en forms (reset por source change); `clearTrigger` solo en selects; form emite `{ id, data: SaveModel }`; submit con `(ngSubmit)` + `FormsModule`, o botón `(clicked)` sin evento de form
- [ ] Select emite `Model | null` (`selectedItem`); consumidor agrega el modelo directo a su lista; selected-list emite `delete`
- [ ] Labels asociados a controles; elementos interactivos focusables con keydown
- [ ] Auth consistente: **[CSR]** Bearer de `localStorage`/`sessionStorage`; **[SSR]** por namespace (sessionStorage + sessionSignal reactivo + interceptor con refresh/retry/logout)
- [ ] Feedback: `ErrorService` (modal, vía interceptor) + `SuccessService` (toast) + `ConfirmService` (promise-based)
- [ ] Badge/estado real-time: `NotificationBadgeState` con WebSocket primario (observador server 5s) + polling 30s solo como fallback; `disconnect()` en logout (efecto `isAuthenticated`)
- [ ] Búsquedas con `encodeURIComponent()`; `limit` de paginación acotado
- [ ] `strict: true`; comillas simples y semicolons uniformes; imports con aliases (`@core/*`, `@shared/*`, `@features/*`)
- [ ] Nomenclatura singular: `-component` (sin `s`) en archivos, clases y selectores
- [ ] `pnpm` (nunca `npm`)

---

## 9. Errores comunes (anti-patrones)

| Anti-patrón | Por qué evitarlo |
|-------------|------------------|
| **[SSR]** `npm start` con `ng serve` | Es el dev server sin SSR; producción requiere el servidor Express (`node dist/.../server.mjs`) |
| `subscribe()` manual en listados | Estado no reactivo, propenso a leaks y a estados stale; usar `rxResource` |
| `(submit)` en lugar de `(ngSubmit)` | Enter recarga la página y pierde el form |
| `(ngSubmit)` **sin `FormsModule` importado** | El evento `ngSubmit` lo emite el directive `NgForm`; sin `FormsModule` en los imports del componente **nunca dispara** y el form hace submit nativo (recarga GET sin enviar POST) — el botón `type="submit"` queda mudo |
| WebSocket + polling simultáneos como canales de badge | Doble tráfico y complejidad; usar el WS como canal primario y el polling solo como fallback cuando el WS cae, con `disconnect()` limpio en logout |
| Outputs `onXxx` (`onClick`, `onSubmit`, `onClose`) | Confunde con listeners DOM; la regla `no-output-on-prefix` lo prohíbe |
| Outputs con nombre de evento nativo (`close`, `click`, `submit`) | La regla `no-output-native` lo prohíbe; usar `closed`/`clicked`/`submitted` |
| `isLoading()` solo para el spinner | Desmonta la lista en cada refetch; usar `isLoading() && !hasValue()` |
| **[SSR]** `JSON.parse(text)` directo en el servidor | Una respuesta no-JSON del backend explota con 502 genérico; usar un helper seguro que devuelva `{ detail }` |
| **[SSR]** Escribir signals en el constructor | NG0950 en SSR; usar `effect()` |
| Labels sin control asociado | Rompe accesibilidad (`label-has-associated-control`); usar `span`/`div` para decorativos |
| Interactivos click-only | Inaccesibles por teclado; agregar `role`, `tabindex` y keydown |
| `errorService.show()` duplicado en páginas | Doble manejo de errores; el interceptor es la única fuente |
| Paginación sin tope (`limit` ilimitado) | El backend responde 422; acotar a 1-100 |
| `getAllPayload` con side-effects en el `map` | Paginación stale al fallar una request |
| Comillas dobles / imports relativos | Inconsistencia que rompe el lint; usar comillas simples + aliases |
| Verificar outputs con `OutputEmitterRef` como si fueran funciones | Confundir método handler y output homónimo (colisión de nombres); renombrar el método |
| Signals sueltas para estado de feature | `dataList`, `isLoading`, `isSaving`, `showModal`, `selectedItem` como signals individuales dispersos → difícil de rastrear; agrupar en un objeto por feature |
| Select emitiendo `number` (`newSelectedId`) | Obliga al consumidor a un **segundo fetch** del catálogo para resolver id → modelo (doble fetch) y hace el contrato ambiguo; el select debe emitir el modelo completo (`selectedItem = output<Model \| null>()`) y el consumidor lo agrega directo |
| `templateUrl` apuntando a nombre viejo tras renombrar archivo | El componente compila pero el template no se carga; actualizar `templateUrl` junto con el nombre del archivo |
| Componentes sin `ChangeDetectionStrategy.OnPush` | Default revisa todo el árbol en cada ciclo; con signals y sensores dejados sin marcar se pierde rendimiento y consistencia — salvo componentes legacy que muten estado en callbacks no reactivos (ver §4.5.1) |