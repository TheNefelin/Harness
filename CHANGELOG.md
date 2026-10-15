# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es/1.1.0/); versionado semántico.

## [0.2.0] - 2026-10-14

### Añadido

- `tools/check.ps1`: verificador determinista del catálogo (estructura de skills, solapamiento de triggers, evals de disparo y frescura de las claims). Sale 0/1, como `install.ps1 -Doctor`.
- `evals/triggers.json`: 24 casos `{prompt, expect}` que cubren las 16 skills y los límites `NO para`.
- `.github/workflows/check.yml`: ejecuta el verificador en push/PR y mensualmente (detección de drift).
- `.gitattributes`: normaliza los saltos de línea a LF (evita falsos `CONFLICT` por CRLF al comparar hashes).
- `install.ps1`: `-Detect -Verbose` muestra la **evidencia** (marcador) de cada tecnología; `.harness.json` incluye ahora `schemaVersion` y se escribe **sin BOM**; guard de `schemaVersion` (avisa si falta, **aborta** si el manifiesto trae uno más nuevo que el soportado).
- `evals/triggers.json`: esquema enriquecido (`id`, `tipo` positivo/ambiguo/negativo, `nota`) y **32 casos** (+3 ambiguos de frontera y +5 negativos sobre los 24 iniciales).

### Cambiado

- `tools/check.ps1`: los evals aceptan `expect: "none"` o `null` → exige que **ninguna** skill se active; resumen con desglose por `tipo` y `id` en los fallos. El reporte de solapamiento ahora es **accionable** (muestra términos compartidos, acción sugerida y un top-3 de seguimiento). La frescura acepta también el estilo `verificado:`.
- `skills/sql`: `description` ampliada (postgres, consulta lenta, explain, índice) — un eval de frontera destapó que un prompt SQL realista no la activaba.

### Documentación

- README: sección **Verificación** y árbol de estructura actualizados; tabla de marcadores de `-Detect`, alcance intencional (openCode), regla de versionado (SemVer), estrategia de migración de `schemaVersion`, justificación del umbral de solapamiento (0,5 vs max 0,25), onboarding de colaboradores (skills gitignored) y hoja de ruta con el diferido de portabilidad/tests.
- `CONTRIBUTING.md`: guía para añadir/editar skills y evals, checklist de PR (incluye el criterio de solapamiento Jaccard) y convenciones.
- `tools/check.ps1`: portabilidad de separadores de ruta (LF/cross-platform).

## [0.1.0] - 2026-10-13

### Añadido

- Catálogo inicial de 16 skills, reglas `AGENTS.md`, plantillas de contexto e `install.ps1` (instalación global o por proyecto, `-Detect`, `-Doctor`, `-WhatIf`, `-Source`).
