# Feedback de usuario (Error/Success/Confirm)

> Detalle de la sección **Feedback de usuario** de la skill `angular`.

- **Error → `ErrorService`** (modal): `errorService.show(msg)` setea una signal única; los layouts renderizan el modal. El `errorInterceptor` lo dispara automáticamente ante cualquier HTTP error (única fuente; las páginas no llaman `errorService.show`).
- **Éxito → `SuccessService`** (toast): `show(msg)` acumula en cola (`ToastModel[]`), auto-cierre a los 5s + cierre manual. Solo en operaciones de escritura.
- **Confirmación → `ConfirmService`** (promise-based): `await confirmService.confirm({ title, message })` resuelve `boolean`. La página **nunca** toca los outputs del modal (`confirm`/`closed`), solo espera el boolean.
- **Validaciones de formulario** → componente local de mensaje, nunca toast/modal.
- **Mensajes de error reales**: `err?.error?.detail || err?.message || fallback` — el interceptor ya formatea, no sobrescribir con genéricos.
