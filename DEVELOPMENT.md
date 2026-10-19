# Desarrollo

> Memoria del proyecto: aquí viven las decisiones y el estado que deben sobrevivir a cada sesión.
> Marca el **estado** de cada decisión (`Aceptado`, `Propuesto`, `Pendiente`); lo desconocido se anota, no se inventa.
> Reemplaza el estado caducado en vez de acumular un diario de cada sesión.

## Arquitectura

Catálogo de **reglas** (`AGENTS.md`), **skills** (`skills/<nombre>/SKILL.md` + `references/`) y **plantillas de contexto** (`templates/`) para openCode, más el **instalador** (`install.ps1`) y las **herramientas de verificación** (`tools/check.ps1`, `tools/test.ps1`).

- **Instalación** (`install.ps1`): copia gestionada de skills/reglas a **global** (`~/.config/opencode/`) o **local** (`<proyecto>/harness/`), con manifiesto `.harness.json` y marcador `.harness-source` por skill; poda y respalda en `.harness-backup`. Idempotente (`-Update`) y sin guardar rutas absolutas.
- **Skills**: se cargan **bajo demanda** (la `description` siempre; el cuerpo al activarse). El detalle vive en `references/*.md` (**progressive disclosure**), citado desde el `SKILL.md`.
- **Verificación**: `tools/check.ps1` valida estructura, referencias alcanzables, solapamiento (Jaccard), evals y frescura; `tools/test.ps1` son pruebas de integración. El CI (`.github/workflows/check.yml`) corre ambos en `windows-latest` + `ubuntu-latest`.

## Decisiones técnicas

| Fecha | Estado | Decisión | Motivo | Alternativas descartadas |
|---|---|---|---|---|
| 2026-10-13 | Aceptado | Reglas duras (idioma, permisos, Git) en `AGENTS.md`; el detalle técnico en skills | Lo transversal debe estar **siempre** activo; el detalle se carga solo al hacer falta | Meter todo en las reglas (infla cada sesión) |
| 2026-10-14 | Aceptado | Los archivos de apoyo de una skill **no** se cargan solos: el `SKILL.md` los cita | El agente lee `references/` solo cuando el `SKILL.md` se lo indica | Cargar la skill completa siempre |
| 2026-10-14 | Aceptado | `check.ps1` exige que cada `references/*.md` sea **citada y alcanzable** desde su `SKILL.md` | Evita referencias huérfanas (detalle que nunca se lee) | Revisión manual |
| 2026-10-14 | Aceptado | Evals de disparo como **heurísticas de routing** (proxy léxico), no como validación del mecanismo | No ejecutan openCode; detectan solapamiento y regresión, no el routing real | Prometer validación real |
| 2026-10-14 | Aceptado | PowerShell único (sin bash ni Node); multiplataforma con PS 7+ y CI `windows-latest` + `ubuntu-latest` | Una sola implementación; portabilidad **probada**, no supuesta | Bash; Node |
| 2026-10-14 | Aceptado | Las reglas viven en **un solo** scope; el otro aporta skills con `-SkillsOnly` | openCode combina global + proyecto: dos copias idénticas de reglas no aportan | Instalar reglas en ambos scopes |
| 2026-10-19 | Aceptado | Plantillas en **sintaxis V2** de openCode: `permissions` (array), `shell`, `skills` (array) | El objeto `permission` y `skills.paths` está **obsoleto** en V2 | Mantener V1 |
| 2026-10-19 | Aceptado | `read` **deniega** `.env`/`.env.*` pero **permite** plantillas sin valores reales (`.env_demo`, `.env.example`, `.env.sample`, `.env.template`) | Las plantillas son seguras y estándar; los secretos, no | Denegar todo `.env.*` |
| 2026-10-19 | Aceptado | Solo el **usuario** commitea/pushea; el agente entrega el mensaje | Control total del historial | El agente commitea |
| 2026-10-19 | Aceptado | El **detalle de subsistema** de una skill (con su código) vive en `references/`; el `SKILL.md` queda en reglas + anti-patrones + punteros | `SKILL.md` scaneable y `MaxBodyLines` con holgura; el detalle se lee solo al hacer falta | Inline (rozaba el límite de 400) |

## Estado

- [x] **0.2.0**: portabilidad multiplataforma, referencias alcanzables, `-Detect` en monorepo, `.env.example`, sintaxis V2 de las plantillas.
- [x] **Progressive disclosure**: `angular`/`astro`/`dotnet`/`fastapi` mueven el detalle de subsistema a `references/`; ninguna skill supera el 80% de `MaxBodyLines` (400).
- [x] Catálogo: **17 skills**, **49 casos** de eval, **99 pruebas** de integración; `check.ps1 -Strict` en 0.

## Pendientes

- **Matizados (sin acción):** `AGENTS.md` frente a `permission` (defensa en capas, no duplicación) y marcadores de frescura donde no aplican.

## Problemas conocidos

- `check.ps1` **no** puede exigir marcador de frescura a todas las skills: algunas (p. ej. `nosql`) lo omiten por diseño porque no están atadas a versiones.

## Deuda técnica

- Las skills instaladas son **artefactos**: no se editan en el proyecto; el catálogo (este repo) es la fuente y `-Update` las refresca.
