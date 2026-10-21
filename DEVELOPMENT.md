# Desarrollo

> Memoria del proyecto: aquí viven las decisiones y el estado que deben sobrevivir a cada sesión.
> Marca el **estado** de cada decisión (`Aceptado`, `Propuesto`, `Pendiente`); lo desconocido se anota, no se inventa.
> Reemplaza el estado caducado en vez de acumular un diario de cada sesión.
> Empieza por el **Mapa del proyecto**: apunta a dónde mirar sin re-escanear el código.

## Mapa del proyecto

Índice puntero: **qué leer y cuándo**, para no re-escanear el código. El detalle vive en el destino; lee la fila del área y abre solo ese destino.

| Área / tema | Dónde mirar | Cuándo leerlo |
|---|---|---|
| Reglas duras (idioma, permisos, Git, `.env`) | `AGENTS.md` | Siempre activo; al operar en cualquier repo |
| Catálogo de skills | `skills/<nombre>/SKILL.md` (+ `references/`) | Al tocar una skill o su tecnología |
| Instalación / desinstalación | `install.ps1` (cabecera `.PARAMETER`) y `README.md` | Al cambiar scopes, manifiesto, `-Detect`/`-Doctor`/`-Uninstall` |
| Plantillas de contexto | `templates/` | Al sembrar/actualizar `README.md`/`DEVELOPMENT.md`/`SKILL.md` de un proyecto |
| Verificación | `tools/check.ps1` (estructura/solapamiento/frescura/encoding) y `tools/test.ps1` (integración) | Antes de cerrar cualquier cambio |
| Memoria y contexto | Este archivo (`DEVELOPMENT.md`) + `AGENTS.md` §4 | Antes de trabajar en cualquier área |
| Tarea en curso (efímera) | `.harness/session.md` (local, fuera de Git) | Al pausar/retomar una tarea larga |

## Arquitectura

Catálogo de **reglas** (`AGENTS.md`), **skills** (`skills/<nombre>/SKILL.md` + `references/`) y **plantillas de contexto** (`templates/`) para openCode, más el **instalador** (`install.ps1`) y las **herramientas de verificación** (`tools/check.ps1`, `tools/test.ps1`).

- **Instalación** (`install.ps1`): copia gestionada de skills/reglas a **global** (`~/.config/opencode/`) o **local** (`<proyecto>/harness/`), con manifiesto `.harness.json` y marcador `.harness-source` por skill; poda y respalda en `.harness-backup`. Idempotente (`-Update`) y sin guardar rutas absolutas.
- **Skills**: se cargan **bajo demanda** (la `description` siempre; el cuerpo al activarse). El detalle vive en `references/*.md` (**progressive disclosure**), citado desde el `SKILL.md`.
- **Verificación**: `tools/check.ps1` valida estructura, referencias alcanzables, solapamiento (Jaccard), evals, frescura y encoding; `tools/test.ps1` son pruebas de integración. El CI (`.github/workflows/check.yml`) corre ambos en `windows-latest` + `ubuntu-latest`.

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
| 2026-10-19 | Aceptado | **openCode V2 obligatorio**: la configuración usa `permissions`/`shell`/`skills`; no se soporta V1 | V1 **rechaza** el bloque de permisos (`ConfigInvalidError`, observado en vivo): la app no carga la config y se perderían las protecciones (`.env`/edición/shell) | Soportar ambas sintaxis (en V1 el bloque no tiene efecto) |
| 2026-10-19 | Aceptado | Las plantillas **deniegan** las mutaciones de Git (`commit`/`push`/`pull`/`merge`/`rebase`/`cherry-pick`/`reset`/`revert`/`restore`/`stash`) | No depender solo del `ask`: el agente nunca muta Git (coherente con §9). Los **comandos compuestos se segmentan** (ver más abajo): cada segmento se evalúa por separado y el `deny` gana | Dejar solo `ask` (admite aprobación) |
| 2026-10-19 | Aceptado | `AGENTS.md` se mantiene como **un solo archivo** (no se parte en skills) | Las reglas duras (idioma, `.env`, Git, permisos) deben **cargarse siempre**; partirlas las volvería condicionales | Mover formato de commit/tests a skills (ahorro marginal, riesgo de perder reglas duras) |
| 2026-10-20 | Aceptado | `DEVELOPMENT.md` abre con un **Mapa del proyecto** (índice puntero "área → dónde mirar → cuándo"); `AGENTS.md` §4 arranca por él y enlaza el checkpoint `.harness/session.md` | Separar *qué leer* de *dónde está* evita leer el `DEVELOPMENT.md` entero y re-escanear el código (menos tokens, menos alucinación). Se adopta el puntero + worklog del estudio `rsc-harness` **sin** su wiki/cron/plugins (PowerShell único) | Volcar la memoria entera en el archivo de cada turno (lo que se quería evitar); carpeta wiki multiformato (sobre-ingeniería para este tamaño) |
| 2026-10-20 | Aceptado | `-Uninstall` retira **por pertenencia**, no por carpeta: recorre skills (marcador `.harness-source`), reglas (`rules:true` o hash == catálogo) y `instructions` (`created.instructions`); lo gestionado **se mueve a `.harness-backup`** y los directorios solo se borran si quedan **vacíos** | Un `Remove-Item $ScopeRoot -Recurse` borraba `~/.config/opencode/` entero en Global (config, plugins, otros agentes) y archivos propios en `harness/`; y comprobaba los respaldos **después** de borrarlos. La promesa "solo lo gestionado" debe cumplirse por **propiedad**, no por ubicación | Advertir sin cambiar el alcance (el daño ya está hecho); borrar la carpeta y confiar en que el usuario no tenga nada ajeno |
| 2026-10-20 | Aceptado | `git remote` deja de permitirse en bloque: `git remote*` → `deny` (cubre `remove`/`set-url`/`add`) y `git remote -v *` → `allow` (consulta), con la regla específica **después** (*last match wins*) | `git remote*` permitía **mutar** remotos sin confirmar, contradiciendo §9 | Mantener `allow` amplio (permite mutación silenciosa) |
| 2026-10-20 | Aceptado | Tras `-Uninstall` Local, el `.gitignore` **conserva la línea `harness/.harness-backup/`** (y la cabecera) mientras queden respaldos, con **aviso accionable** al cierre | Los respaldos (copia de `AGENTS.md`/skills) quedaban en disco sin ignorar → aparecían como **no rastreados** y podían entrar en un commit por descuido. Quitar el bloque completo dejaba una trampa; conservar solo esa línea deja el repo consistente sin obligar a recordar nada | Quitar todo el bloque y solo avisar (deja la trampa); conservar la línea siempre (entrada huérfana si el usuario borra los respaldos) |
| 2026-10-20 | Aceptado | `Move-ToBackup`/`Backup-Path` **desambiguan** el sello cuando el destino ya existe (`Nombre-sello-N`) | El sello por segundo colisionaba al respaldar dos veces el **mismo nombre** en el mismo segundo: `Move-Item` fallaba y **abortaba la desinstalación a medias** (respaldo incompleto). *Friction proportional to risk*: un respaldo que falla no puede tumbar la operación | Confiar en la granularidad de segundo (bug real, reproducido) |
| 2026-10-20 | Aceptado | `-Source` valida el catálogo **completo** (`skills/` + `AGENTS.md` + las tres plantillas) **antes** de desplegar | Un clon incompleto pasaba el chequeo (solo miraba `skills/`) y **abortaba a mitad**, tras desplegar skills/reglas pero antes de escribir `.harness.json` → scope irreconocible por `-Update`/`-Uninstall`/`-Doctor`. *Evidence over claims*: mejor fallar claro y temprano | Validar solo `skills/` y esperar que el resto exista |
| 2026-10-20 | Aceptado | `-Update` desde manifiesto **tolera** una skill retirada del catálogo (avisa, omite y la poda); con `-Skills` explícito un nombre inexistente **falla fuerte** | Asimetría por origen del dato: el set del manifiesto lo eligió el instalador (un nombre ausente = el catálogo **retiró** la skill, y abortar en bloque impedía refrescar el resto); el set de `-Skills` lo escribió el usuario (un nombre ausente = casi seguro **error de tecleo**, y conviene verlo). *Friction proportional to risk* | Abortar en bloque siempre (asimetría con `-Doctor`, que ya tolera) o tolerar siempre (deja pasar typos) |
| 2026-10-20 | Aceptado | El bloque del `.gitignore` se escribe con `[System.IO.File]::WriteAllText(..., UTF8Encoding($false))`, respetando el salto del archivo (LF si es nuevo, sin línea en blanco inicial) | `Add-Content` sin `-Encoding` usa ANSI en PS 5.1 → corrompía acentos/`ñ` de un `.gitignore` propio y rompía la regla UTF-8/LF del repo; además el bloque nuevo abría con línea en blanco | `Add-Content` (encoding por defecto, específico de Windows) |
| 2026-10-21 | Aceptado | `check.ps1` verifica el **encoding** del texto versionado (UTF-8 sin BOM, LF; `.ps1` ASCII) | La regla estaba escrita en `CONTRIBUTING.md` pero **nadie la verificaba**: se revisaba a mano y se podía romper en silencio. Al automatizarla destapó un `¿` no-ASCII real en `install.ps1`. *Evidence over claims*: una regla sin verificación es una promesa | Revisar a mano en cada cambio (frágil, no cubierto por CI) |
| 2026-10-21 | Aceptado | **No** endurecer la política `read *: allow` (p. ej. añadir `*.pem`/`~/.ssh`) | Es el default **fail-open** de openCode y cambiarlo crearía reglas que el cliente ya aplica o conoce (mantenimiento divergente); los denies cosméticos que no cubren el caso real son **seguridad teatral**. Se **documenta** que el fail-open es deliberado | Añadir denies cosméticos de secretos en la plantilla |
| 2026-10-21 | Aceptado | `-Adopt` es un **informe de solo lectura** (imprime el diff, nunca escribe; sin modo de aplicación, ni con `-Force`) | Cierra el caso "el `.md` tiene contenido y no sigue el estándar". Reescribir docs ajenas es destructivo → el Harness **muestra** y el usuario decide. *Friction proportional to risk*: nada se aplica sin una acción aparte | Modo que aplique el diff (o lo fusione) con `-Force`; tocar `.md` con contenido |
| 2026-10-21 | Aceptado | El diff de `-Adopt` se calcula con **LCS** propio (determinista, sin depender de `git`) | `git diff --no-index` sale 1 con diferencias (confunde informativo con error), pinta rutas absolutas y exige git; un LCS en PowerShell es corto, portátil y da un formato legible (`-`/`+`) | Delegar en `git diff --no-index` y parsear su salida |
| 2026-10-21 | Aceptado | `check.ps1` verifica la **coherencia del inventario** (N skills / N casos declarados en `README.md`/`DEVELOPMENT.md` == catálogo real) | Una auditoría externa dudó del conteo (dijo 16 skills; eran 17): era un falso positivo, pero reveló que **nadie verificaba** que el texto no se desincronizara del catálogo. *Evidence over claims*: automatizar el conteo evita el drift silencioso que sí sería un defecto real | Confiar en actualizar el conteo a mano en cada cambio |
| 2026-10-21 | Aceptado | `-Doctor` **audita la memoria** del proyecto (Local): avisa si faltan `README.md`/`DEVELOPMENT.md`/`SKILL.md`, si existen **vacíos**, o informa del checkpoint; sugiere `-Context` | `-Context` es **opt-in**, así que un usuario puede instalar reglas+skills sin la memoria que sostiene la continuidad (hallazgo real de la auditoría). La mitigación es **detectar y avisar**, no sembrar a la fuerza: `-Context` sigue siendo la decisión del usuario | Hacer `-Context` implícito (pisaría/sembraría sin pedirlo, contrario a "nunca reescribir docs ajenas") |

## Estado

- [x] **0.2.0**: verificador (`check.ps1`), evals de disparo, CI, instalador base (`-Detect`/`-Doctor`/`-Global`) y skills base (godot/aws/azure/oci/harness-install).
- [x] **0.3.0**: openCode V2 obligatorio, portabilidad multiplataforma, referencias citadas/alcanzables, `-Detect` en monorepo, `-SkillsOnly`/`-IncludeRules`, checkpoint de sesión, `DEVELOPMENT.md` y plantillas endurecidas (deny de Git).
- [x] **Progressive disclosure**: `angular`/`astro`/`dotnet`/`fastapi` mueven el detalle de subsistema a `references/`; ninguna skill supera el 80% de `MaxBodyLines` (400).
- [x] Catálogo: **17 skills**, **49 casos** de eval, **283 pruebas** de integración; `check.ps1 -Strict` en 0.
- [x] **Adopción segura** (2026-10-20): `-Context` siembra plantillas en `.md` existentes pero **vacíos**; `AGENTS.md` §4 exige **leer la memoria primero** (anti-scrapeo); `-Doctor` verifica el **cliente openCode V1/V2**; `-Uninstall` desinstala **por pertenencia** (respeta tu código y tu documentación, conserva respaldos y contenido ajeno, también en scope Global).
- [x] **`check.ps1` con 7 secciones** (2026-10-21): suma **Inventario** (el conteo declarado de skills/casos en `README.md`/`DEVELOPMENT.md` debe coincidir con el catálogo real: evita el drift silencioso que una auditoría confundiría con un defecto).
- [x] **`-Doctor` audita la memoria** (2026-10-21): en Local avisa si faltan o están vacíos `README.md`/`DEVELOPMENT.md`/`SKILL.md`, e informa del checkpoint; sugiere `-Context`. Cierra la "dependencia silenciosa de `-Context`" señalada por la auditoría, sin sembrar a la fuerza.
- [x] **Segmentación de comandos compuestos: verificada** (2026-10-21): la doc oficial de openCode V2 confirma que los comandos compuestos producen **varias** evaluaciones de permiso (una por segmento), así que el `deny` de mutaciones de Git protege aunque el comando venga encadenado (`git status && git push`). `shell *: ask` es la red de respaldo. Se retira el "sin verificar".

## Memoria: propuesta (estudio de `ericrisco/rsc-harness`)

Objetivo declarado por el usuario: que el agente **sepa sin escrapear** el código, **ahorre tokens** y **evite alucinaciones** (memoria estructurada, no re-lectura). Simple y conservador, pero tan capaz como la referencia. Estudio hecho en local (`D:\Repo\Others\rsc-harness`, solo lectura). **Estado: Propuesto — sin implementar.**

### Cómo lo resuelve la referencia (hechos)

- **La memoria es una wiki, no un archivo.** `02-DOCS/` (Karpathy "LLM wiki"): `inbox/` (drop zone de cualquier formato) → `raw/` (fuente inmutable) → `wiki/` (artículos compilados con frontmatter YAML + enlaces markdown + `index.md`/`log.md`/`gaps.md`/`scores.json`). El agente **escribe** la wiki; el humano la lee (Obsidian). Sin vector DB, sin embeddings, sin RAG: **estructura, no similitud**.
- **Anti-scrapeo = puntero fijo, no índice completo.** El `CLAUDE.md` raíz (leído en **cada** turno, tope ~200 líneas) guarda un `## Knowledge map` **corto** que apunta a `wiki/index.md` (el índice completo, que crece libre). Regla: *"lee el artículo del área antes de trabajar en ella"*.
- **Dos on-ramps de captura.** (1) *Inbox Sweep*: el usuario suelta archivos y el agente "sale a pasear" y los compila. (2) *Worklog Sweep*: cada sesión con señal durable (archivos cambiados, decisión, commit) escribe `raw/worklog/<fecha>-<slug>.md` (qué hicimos, por qué, archivos, resultado, pendientes) y se compila a `wiki/`.
- **Runtime (lo caro):** hooks de ciclo de vida (`SessionStart` inyecta memoria; `PreCompact`/`SessionEnd` recuerdan escribir el worklog), plugins por cliente (`opencode-memory-plugin.js`), un core de ~39 KB, retención 30 días, tope de contexto 4 KB, y "lecciones" puntuadas.
- **Curaduría automática:** Maintenance Pass / Micro-Improve / Deep Improve con cron; `log.md` inmutable (newest-first), `gaps.md` append-only, sin resolución automática de conflictos.

### Lectura crítica para nuestro Harness

- **Lo que encaja con el objetivo:** (a) memoria como **conocimiento destilado con puntero**, no volcado; (b) **"lee antes de trabajar en tu área"** — es *exactamente* el antídoto al escrapeo; (c) **frontera raw→wiki** (evidencia vs. destilado); (d) índice **fuera** del archivo de cada turno; (e) **worklog** de sesión.
- **Lo que NO encaja (sobre-ingeniería para nuestro tamaño):** wiki multiformato + Obsidian + `.base` + OKF; **plugins y hooks por cliente** (nosotros somos "PowerShell único, sin Node"); curaduría por cron y scores automáticos. Somos una implementación **simple y conservadora** (lo dice el README) y **no reutilizamos su código**.
- **Decisión clave:** *quién* mantiene la memoria. En la referencia es **automático**; en el nuestro la memoria se **cura con permiso** (§5). Mantener nuestro modelo es más seguro; adoptar el automático exigiría hooks/plugins que rompen "PowerShell único".

### Opciones (a decidir por el usuario)

1. **Mínimo (recomendado).** Mantener `DEVELOPMENT.md` como memoria y arreglar dos huecos concretos:
   - `-Context` siembra la plantilla cuando el `.md` existe **vacío** (0 B); si tiene contenido, **respeta**.
   - Regla explícita en `AGENTS.md` §4: **leer `DEVELOPMENT.md` antes de trabajar** en el área (hoy se infiere; hacerlo explícito es lo que evita el escrapeo).
   - Coste: 2 cambios pequeños. No cambia la convención.
2. **Memoria+índice (medio).** Lo anterior **más** un **índice** del proyecto en `DEVELOPMENT.md` (tabla "artículo → cuándo leerlo") que separa *qué leer* de *dónde está*, más un **worklog** de sesión (plantilla `raw/`-like) con disparo por *checkpoint* de sesión (ya existe `.harness/session.md`). Sin carpeta wiki, sin cron, sin plugins.
3. **Adoptar el patrón wiki (grande).** Carpeta de documentación (`docs/` o `02-DOCS/`-like) como wiki + `index.md`/`log.md`, y actualizar `AGENTS.md` §4/§13, `templates/`, `install.ps1` y `README`. Rediseño de convención; solo si de verdad se va a usar el volumen.

**Recomendación:** empezar por la **1** (barata, corrige lo que falló en `LaserBoy-Arduino`) y tratar la **2** como siguiente paso natural. La **3** solo con uso real que la justifique.

### Estado de la implementación

- [x] **Opción 1 implementada** (2026-10-20): `-Context` siembra plantillas cuando el `.md` existe **vacío** (`Test-EmptiedFile`); `AGENTS.md` §4 gana la regla explícita de **leer la memoria primero**. Pruebas: `tools/test.ps1` 123 → **135**.
- [x] **Hueco V1/V2 cerrado** (2026-10-20): `install.ps1 -Doctor` detecta la **versión del cliente** (`Get-OpenCodeClient`): V2 OK, V1 **falla**, ausente avisa.
- [x] **Desinstalación limpia** (2026-10-20): `install.ps1 -Uninstall` retira **por pertenencia** (skills con marcador, reglas por `rules:true`/hash, `instructions` por `created.instructions`) y deja el proyecto "sin Harness, con el avance del usuario". Lo gestionado **se mueve a `.harness-backup`**; lo ajeno (skills sin marcador, archivos propios en `harness/`, config/plugins de `~/.config/opencode`, `opencode.json`/`.gitignore` preexistentes, `.md` sembrados) **se conserva**; los directorios solo se borran si quedan vacíos. **Corregido** tras auditoría: antes borraba `ScopeRoot` entero (crítico en Global) y comprobaba los respaldos tras borrarlos. Pruebas: 159 → **266** (incluye scope global y pertenencia; `.gitignore` conserva la línea de respaldos; `-Force` + `AGENTS.md` ajeno; sin colisión de sello; `-Source` incompleto; `-Context` en Global; `-Update` tolera skill retirada; `.gitignore` UTF-8 sin BOM; sección **Encoding** de `check.ps1`; `-Adopt` de solo lectura).
- [x] **`-Adopt` implementado** (2026-10-21): informe **de solo lectura** (scope Local) del diff entre los `.md` de memoria y las plantillas; **nunca escribe**. Cierra el caso "el `.md` tiene contenido y no sigue el estándar". Diff por **LCS** propio (sin depender de git) con salvaguarda posicional para archivos grandes. Pruebas: 249 → **266**.
- [x] **Opción 2 implementada** (2026-10-20): **Mapa del proyecto** en `DEVELOPMENT.md` (y su plantilla) como índice puntero; `AGENTS.md` §4 arranca por el mapa (no lee el archivo entero) y enlaza el **checkpoint** `.harness/session.md` como worklog de la tarea activa. Sin carpeta wiki, sin cron, sin plugins. Pruebas: 158 → **159**.
## Pendientes

- **Matizados (sin acción):** `AGENTS.md` frente a `permissions` (defensa en capas, no duplicación) y marcadores de frescura donde no aplican.
## Problemas conocidos

- `check.ps1` **no** puede exigir marcador de frescura a todas las skills: algunas (p. ej. `nosql`) lo omiten por diseño porque no están atadas a versiones.
- El patrón `*.env.*` (deny, alineado con el default de openCode) también **bloquea** nombres legítimos como `app.env.ts`: no hay glob que case "basename empieza por `.env`" porque `*` cruza `/`. Se mantiene **fail-closed** (protege `.env.local`/`.env.production`, que es lo importante).
- La política `read *: allow` es **fail-open** (el default de openCode): protege `.env`/`.env.*`, pero **no** `*.pem`/`*.key`/`~/.ssh`. Es **decisión consciente** (2026-10-21): no se añaden denies cosméticos que el cliente ya aplica o conoce. La protección real de secretos vive en el default del cliente, no en la plantilla.
- **Verificado (no repetir)**: `.env_demo` **NO** lo bloquea `*.env.*`. La especificación de *matching* de openCode V2 dice que el punto es **literal** (`*` es comodín; el resto de caracteres, literales), así que `*.env.*` exige la secuencia `.env.` y `.env_demo` (guion bajo) no la tiene. Por tanto las plantillas que lo listan como permitido (`AGENTS.md`, `templates/README.md`, `skills/fastapi`) son **correctas**; una auditoría previa lo reportó como contradicción y era un **falso positivo**. Cubierto por prueba de regresión.
- **Segmentación de comandos compuestos (verificado en la documentación oficial de V2).** La especificación de permisos de openCode V2 define el recurso de `shell` como *"Scanner-produced command string; **compound commands may produce several**"*: un comando compuesto como `git status && git push` produce **varias** evaluaciones, una por segmento, y cada patrón se aplica al segmento que le corresponde (`git status` → `allow`, `git push` → `deny`). Por eso el `deny` de mutaciones de Git protege aunque el comando venga encadenado. Matiz (*may*, no *always*): el diseño **no depende** de la segmentación — `shell *: ask` es la red por defecto, así que cualquier segmento no reconocido **pregunta** en vez de ejecutarse. Defensa en capas, no una apuesta. Fuente: `https://opencode.ai/v2/docs/permissions` (matching y recursos de `shell`).

## Deuda técnica

- Las skills instaladas son **artefactos**: no se editan en el proyecto; el catálogo (este repo) es la fuente y `-Update` las refresca.
