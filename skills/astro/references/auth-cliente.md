# Auth cliente — decay-aware + refresh + retry

> Detalle de la sección **Auth cliente** de la skill `astro`. Léelo al tocar login, sesión, `apiFetch` o la UI de auth.

```ts
// src/lib/auth.ts
// Acceso: solo access_token + user en localStorage. El refresh NO vive en el navegador.

export function isTokenExpired(token: string): boolean {
  try {
    const [, payload] = token.split('.');
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const json = atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4));
    const decoded = JSON.parse(json);
    if (typeof decoded.exp !== 'number') return true;
    return decoded.exp * 1000 <= Date.now();
  } catch { return true; } // token corrupto → expirado
}

// Al boot: si el access venció → refresh silencioso; solo logout si el refresh falla.
export async function clearExpiredSession(): Promise<void> {
  const token = getAccessToken();
  if (!token || !isTokenExpired(token)) return;
  const refreshed = await refreshAccessToken();
  if (!refreshed) logout();
}

export function logout(): void {
  void fetch('/api/proxy/auth/logout', { method: 'POST' }); // fire-and-forget
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
  localStorage.removeItem('user');
  window.dispatchEvent(new CustomEvent('authchange')); // la UI se re-sincroniza sola
  showToast('Sesión finalizada', 'info');
}
```

## `auth-ui.ts` — un solo listener (sin leaks)

La UI de auth (login/logout) se centraliza en `lib/auth-ui.ts` con `initAuthUI(elements)`. Registra el listener de `authchange` **una sola vez** — el bug clásico es agregarlo dentro del click de logout y acumular listeners duplicados.

```ts
// src/lib/auth-ui.ts
export function initAuthUI(e: AuthUIElements) {
  // updateUI() lee isAuthenticated() + getUser()
  // logoutBtn → logout() (que dispara authchange → la UI se re-sincroniza sola)
  window.addEventListener('authchange', updateUI);
  // NUNCA registrar el listener dentro de un handler
}
```

Las páginas/componentes solo pasan los elementos del DOM (`loginSection`, `userSection`, `loginBtn`, `logoutBtn`, `avatar`, `name`, `email`, `fallbackAvatar`). Un `<script is:inline>` previo a los módulos solo hace **FOUC-prevention** (muestra el estado en el primer paint antes de que carguen los módulos).
