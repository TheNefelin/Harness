# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es/1.1.0/); versionado semántico.

## [0.2.0] - 2026-10-14

### Añadido

- `tools/check.ps1`: verificador determinista del catálogo (estructura de skills, solapamiento de triggers, evals de disparo y frescura de las claims). Sale 0/1, como `install.ps1 -Doctor`.
- `evals/triggers.json`: 24 casos `{prompt, expect}` que cubren las 16 skills y los límites `NO para`.
- `.github/workflows/check.yml`: ejecuta el verificador en push/PR y mensualmente (detección de drift).
- `.gitattributes`: normaliza los saltos de línea a LF (evita falsos `CONFLICT` por CRLF al comparar hashes).
- `install.ps1`: `-Detect -Verbose` muestra la **evidencia** (marcador) de cada tecnología; `.harness.json` incluye ahora `schemaVersion` y se escribe **sin BOM**; guard de `schemaVersion` (avisa si falta, **aborta** si el manifiesto trae uno más nuevo que el soportado).
- `evals/triggers.json`: esquema enriquecido (`id`, `tipo` positivo/ambiguo/frontera/negativo, `nota`) y **43 casos** (31 positivos, 4 ambiguos, 3 de frontera y 5 negativos): cubre las 16 skills, los límites `NO para`, un caso con tildes/ñ (no-ASCII) y fronteras entre skills vecinas.
- `tools/test.ps1`: pruebas de integración auto-contenidas (sin módulos externos) de `install.ps1` y `check.ps1` en un sandbox temporal (instalación local, `-WhatIf`, `-Update` con conflicto y respaldo, `-Detect`, guard de `schemaVersion`, protección de skills ajenas y códigos de salida). Salen 0/1.
- `tools/check.ps1`: rechaza una `description` sin citar que contenga `: ` o ` #` (frontmatter YAML inválido).

### Cambiado

- `tools/check.ps1`: los evals aceptan `expect: "none"` o `null` → exige que **ninguna** skill se active; resumen con desglose por `tipo` y `id` en los fallos. El reporte de solapamiento ahora es **accionable** (muestra términos compartidos, acción sugerida y un top-3 de seguimiento). La frescura acepta también el estilo `verificado:`.
- `skills/sql`: `description` ampliada (postgres, consulta lenta, explain, índice) — un eval de frontera destapó que un prompt SQL realista no la activaba.
- `install.ps1`: lectura robusta de `.harness.json` (JSON corrupto da un error claro en vez de reventar); el marcador `.harness-source` se escribe **sin BOM**; `Get-Catalog` lee el **frontmatter completo** (no solo 30 líneas) para extraer la `description`; al **podar** una skill gestionada, la **respalda** en `.harness-backup` (antes la borraba).
- `skills/github-actions`: `uses` al día (`checkout@v7`, `setup-node@v7`, `upload-artifact@v7`, `download-artifact@v8`, CodeQL `@v4`), matrix de Node solo sobre versiones soportadas (18/20 ya EOL → 22/24) y marcador de frescura; `description` normalizada al bloque `NO para`. La rúbrica destapó que el ejemplo estaba desactualizado.

### Corregido

- `install.ps1`: restaurada la cabecera de `Add-Detected` (un reemplazo previo la había dejado fuera y el script no cargaba). Lo detectó `tools/test.ps1`.
- `skills/docker`, `skills/nosql`: resueltos los marcadores de frescura sin fecha que marcaba `check.ps1 -Strict` — `docker` con fecha `(verificado 2026-10-14)` y `nosql` reformulado como nota de **Alcance** (no atado a versiones).
- Frontmatter: 13 `description` con `: ` (YAML inválido: GitHub y otros parsers lo rechazan) quedan citadas con comillas dobles.
- `skills/angular`: nota de contexto — los nombres concretos (`CrudPage`, `MutationService`, `ApiService`) son de un proyecto de referencia; los principios son portables.
- `install.ps1`: `Get-TreeHash` calculaba la ruta relativa con `Substring($Path.Length)`; con una ruta **corta 8.3** (p. ej. `RUNNER~1`, la de `%TEMP%` en el runner de CI) los hijos devuelven `FullName` largo y el hash salía mal → toda skill se veía divergente en `-Update` y creaba `.harness-backup` (falso conflicto, CI en rojo). Ahora canonicaliza la raíz con `Get-Item`.
- `skills/harness-install`: la delimitación con `harness-freshness` era **unidireccional**; ahora su `description` también excluye el caso (`NO para ... 'harness-freshness'`).
- `install.ps1`: `.DESCRIPTION` desactualizado — la forma de `.harness.json` ya lista `schemaVersion` (antes omitía la clave que el script escribe y que el README documenta); añadido un bloque `.NOTES` con el diagnóstico `-Verbose` y el puntero a `tools/test.ps1`.

### Documentación

- README: sección **Verificación** (incluye las pruebas de integración) y árbol de estructura actualizados; tabla de marcadores de `-Detect`, alcance intencional (openCode), regla de versionado (SemVer), estrategia de migración de `schemaVersion`, justificación del umbral de solapamiento (0,5 vs max 0,25), onboarding de colaboradores (skills gitignored) y hoja de ruta con el diferido de portabilidad.
- `CONTRIBUTING.md`: guía para añadir/editar skills y evals, checklist de PR (incluye `tools/test.ps1` y el criterio de solapamiento Jaccard) y convenciones.
- `CONTRIBUTING.md`: **rúbrica de una skill** — separa lo universal (description con `NO para`, anti-patrones, honestidad sobre límites, longitud) de lo condicional (`references/` y marcador de frescura), y amplía el checklist del PR.
- `CONTRIBUTING.md`: documenta la estrategia de evals — los negativos son **globales** y la frontera de cada skill la cubren ambiguos/frontera + Jaccard; se decide **no** exigir un negativo por skill (consciente, para no inflar el mantenimiento).
- `.github/workflows/check.yml`: además del verificador, ejecuta `tools/test.ps1` (pruebas de integración).
- `evals/triggers.json`: un negativo usa `expect: "none"` para ejercitar la forma alternativa documentada (el resto usa `null`); `CONTRIBUTING.md` aclara que el matcher normaliza tildes/ñ antes de comparar.
- `tools/check.ps1`: portabilidad de separadores de ruta (LF/cross-platform).

## [0.1.0] - 2026-10-13

### Añadido

- Catálogo inicial de 16 skills, reglas `AGENTS.md`, plantillas de contexto e `install.ps1` (instalación global o por proyecto, `-Detect`, `-Doctor`, `-WhatIf`, `-Source`).
