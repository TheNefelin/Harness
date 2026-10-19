# Toast — bridge SSR + store CSR

> Detalle de la sección **Toast** de la skill `astro`.

`lib/toastTrigger.ts` es el store (solo cliente: `window`/`document`). Como `showToast()` no puede correr en SSR, el contenedor tiene **dos formas**:

1. **Con props `message?`/`type?`** → renderiza un `<div data-ssr-toast>` (bridge): el servidor deja el mensaje en el HTML.
2. **Sin props** → contenedor CSR apilable que se suscribe al store y procesa los bridges `[data-ssr-toast]` de la página (único procesador, montado en Layout).

```ts
// src/lib/toastTrigger.ts
export function showToast(message: string, type: ToastType = 'error'): void {
  const id = nextId++;
  toasts = [...toasts, { id, message, type }];
  emit();
  window.setTimeout(() => dismissToast(id), TOAST_DURATION_MS); // 5s
}
```

**Nota**: el container usa `<section>` con clases propias, **no** `toast toast-end` de DaisyUI — el backdrop-blur funciona bien sin el `translate` del componente de DaisyUI.
