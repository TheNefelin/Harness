# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es/1.1.0/); versionado semántico.

## [0.2.0] - 2026-10-14

### Añadido

- `tools/check.ps1`: verificador determinista del catálogo (estructura de skills, solapamiento de triggers, evals de disparo y frescura de las claims). Sale 0/1, como `install.ps1 -Doctor`.
- `evals/triggers.json`: 24 casos `{prompt, expect}` que cubren las 16 skills y los límites `NO para`.
- `.github/workflows/check.yml`: ejecuta el verificador en push/PR y mensualmente (detección de drift).

### Documentación

- README: sección **Verificación** y árbol de estructura actualizados.

## [0.1.0] - 2026-10-13

### Añadido

- Catálogo inicial de 16 skills, reglas `AGENTS.md`, plantillas de contexto e `install.ps1` (instalación global o por proyecto, `-Detect`, `-Doctor`, `-WhatIf`, `-Source`).
