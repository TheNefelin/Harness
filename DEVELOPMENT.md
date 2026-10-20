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
| 2026-10-19 | Aceptado | **openCode V2 obligatorio**: la configuración usa `permissions`/`shell`/`skills`; no se soporta V1 | V1 **ignora** el bloque de permisos sin avisar (se perderían las protecciones de `.env`/edición/shell) | Soportar ambas sintaxis (en V1 el bloque no tiene efecto) |
| 2026-10-19 | Aceptado | Las plantillas **deniegan** las mutaciones de Git (`commit`/`push`/`pull`/`merge`/`rebase`/`cherry-pick`/`reset`/`revert`/`restore`/`stash`) | No depender solo del `ask`: el agente nunca muta Git (coherente con §9). Falta comprobar si un **comando compuesto** (`git status && git push`) se segmenta y cae en `deny` — **sin verificar** en V2 | Dejar solo `ask` (admite aprobación) |
| 2026-10-19 | Aceptado | `AGENTS.md` se mantiene como **un solo archivo** (no se parte en skills) | Las reglas duras (idioma, `.env`, Git, permisos) deben **cargarse siempre**; partirlas las volvería condicionales | Mover formato de commit/tests a skills (ahorro marginal, riesgo de perder reglas duras) |

## Estado

- [x] **0.2.0**: verificador (`check.ps1`), evals de disparo, CI, instalador base (`-Detect`/`-Doctor`/`-Global`) y skills base (godot/aws/azure/oci/harness-install).
- [x] **0.3.0**: openCode V2 obligatorio, portabilidad multiplataforma, referencias citadas/alcanzables, `-Detect` en monorepo, `-SkillsOnly`/`-IncludeRules`, checkpoint de sesión, `DEVELOPMENT.md` y plantillas endurecidas (deny de Git).
- [x] **Progressive disclosure**: `angular`/`astro`/`dotnet`/`fastapi` mueven el detalle de subsistema a `references/`; ninguna skill supera el 80% de `MaxBodyLines` (400).
- [x] Catálogo: **17 skills**, **49 casos** de eval, **123 pruebas** de integración; `check.ps1 -Strict` en 0.

## Pendientes

- **Matizados (sin acción):** `AGENTS.md` frente a `permissions` (defensa en capas, no duplicación) y marcadores de frescura donde no aplican.
- **`-Adopt` (propuesta, no implementado):** en un proyecto avanzado el Harness **no** reescribe ni estandariza la documentación existente; `-Context` solo crea la plantilla **si falta**, así que un `README.md`/`DEVELOPMENT.md` que ya exista (aunque esté **vacío**) se deja igual y no se aprovecha. Idea: un modo de **solo lectura** que compare los `.md` del proyecto con las plantillas y **proponga** diffs para aprobación. Decisión: nunca por defecto (reescribir docs ajenas es destructivo).
- **Verificar la versión del cliente (propuesta, no implementado):** `install.ps1 -Doctor` solo **avisa** si el `opencode.json` está en sintaxis V1, pero **no** comprueba la versión de openCode instalada. Observado en vivo (`LaserBoy-Arduino`): abrir con la app **V1** un `opencode.json` V2 da **`ConfigInvalidError`** (la V1 **rechaza** el config; no lo ignora en silencio). Conviene que el instalador **detecte V1/V2** y avise o aborte antes de dejar una instalación inservible.

## Problemas conocidos

- `check.ps1` **no** puede exigir marcador de frescura a todas las skills: algunas (p. ej. `nosql`) lo omiten por diseño porque no están atadas a versiones.
- El patrón `*.env.*` (deny, alineado con el default de openCode) también **bloquea** nombres legítimos como `app.env.ts`: no hay glob que case "basename empieza por `.env`" porque `*` cruza `/`. Se mantiene **fail-closed** (protege `.env.local`/`.env.production`, que es lo importante).
- **Sin verificar**: si openCode V2 evalúa cada **segmento** de un comando compuesto (p. ej. `git status && git push`). Hasta comprobarlo en una sesión V2 real, los patrones `allow` de Git (`git status*`) podrían permitir el comando entero sin preguntar; no afirmar lo contrario. Prueba manual pendiente.

## Deuda técnica

- Las skills instaladas son **artefactos**: no se editan en el proyecto; el catálogo (este repo) es la fuente y `-Update` las refresca.
