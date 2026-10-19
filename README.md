# Harness

Conjunto reutilizable de **reglas**, **skills** y **plantillas de contexto** para desarrollar proyectos con [openCode](https://opencode.ai). Se instala **global** (una vez para toda la máquina) o **por proyecto**, según elijas.

## Qué resuelve

- El agente no improvisa: reglas claras en `AGENTS.md`.
- Las skills se cargan **solo cuando hacen falta** → menos tokens por sesión. Dentro de una skill, el detalle vive en `references/*.md` y se lee **bajo demanda** (progressive disclosure).
- El contexto del proyecto persiste entre sesiones (`README` / `DEVELOPMENT` / `SKILL`).
- Tú eliges el alcance: **global** (cero drift) o **por proyecto** (solo lo necesario).

## Estructura

```
Harness/
├─ README.md              # este archivo
├─ CONTRIBUTING.md        # cómo añadir/editar skills y evals
├─ CHANGELOG.md           # historial de versiones
├─ DEVELOPMENT.md         # memoria del proyecto (arquitectura, decisiones)
├─ LICENSE                # MIT
├─ VERSION                # versión del harness
├─ .gitattributes         # normaliza saltos de línea (LF)
├─ AGENTS.md              # reglas        ┐
├─ skills/                # 17 skills     ├─ lo que se instala (global o por proyecto)
├─ templates/
│  ├─ opencode.json       # config del proyecto (instructions + skills + permisos)
│  ├─ README.md           # ┐
│  ├─ DEVELOPMENT.md      # ├─ plantillas de memoria (contexto)
│  └─ SKILL.md            # ┘
├─ install.ps1            # instalador / actualizador
├─ tools/
│  ├─ check.ps1           # verificador del catálogo (estructura, triggers, evals, frescura)
│  └─ test.ps1            # pruebas de integración (install.ps1 / check.ps1)
├─ evals/
│  └─ triggers.json       # casos de disparo por skill
└─ .github/workflows/
   └─ check.yml           # CI: push/PR + mensual
```

## Requisitos

- [openCode](https://opencode.ai) **V2** (o superior). El Harness usa la sintaxis V2 (`permissions`/`shell`/`skills`); openCode **V1 ignora ese bloque sin avisar**, así que se perderían las protecciones (bloquear `.env`, pedir permiso al editar y al ejecutar shell). V1 no es compatible.
- **PowerShell**: Windows PowerShell 5.1 (viene con Windows) o **PowerShell 7+ (`pwsh`)**, que corre también en Linux/macOS.
- Los scripts (`install.ps1`, `tools/check.ps1`, `tools/test.ps1`) son **multiplataforma**: corren en Windows (PowerShell 5.1/7) y en Linux/macOS con **PowerShell 7+ (`pwsh`)**. El CI los ejecuta en `windows-latest` y `ubuntu-latest`.

## Instalación por un agente

Si le pides a un agente de openCode "instala este harness" y le das la URL del repositorio, el agente debe:

1. **Clonar** el repo en un directorio **temporal** (fuera del proyecto): `git clone <url> <temp>`.
2. **Preguntar** al usuario, en una sola tanda:
   - **Scope**: ¿**Local** (solo este proyecto) o **Global** (toda la máquina)?
   - **Skills**: mostrar el catálogo (`install.ps1 -List`) y pedir cuáles quiere.
3. **Ejecutar** el instalador con ese scope y `-Skills`:

   ```powershell
   & "<temp>\install.ps1" -Project "<ruta>" -Skills <a,b,c>   # Local
   & "<temp>\install.ps1" -Global -Skills <a,b>               # Global
   ```
4. **Verificar** con `install.ps1 -Doctor` y **reportar** (skills instaladas, `.harness.json`, avisos).
5. Decir al usuario que **recargue openCode** con `/reload` (no cierra la TUI; si no toma los cambios, reiniciar) y **eliminar** el clon temporal. Sin commit/push.

El set de skills es **obligatorio** (no hay default): **nunca** instales sin confirmar el scope y las skills con el usuario. El procedimiento completo está en la skill [`harness-install`](skills/harness-install/SKILL.md).

## Instalación

Es **agnóstico**: no hay set por defecto. Siempre indicas **qué** skills y **dónde**.

```powershell
# Catálogo disponible (nombre + descripción)
.\install.ps1 -List

# Detectar tecnologías del proyecto y skills faltantes (solo lectura)
.\install.ps1 -Project "D:\ruta\al\proyecto" -Detect

# Diagnosticar la instalación del scope (manifiesto, rutas, reglas, config) sin tocar nada
.\install.ps1 -Project "D:\ruta\al\proyecto" -Doctor
.\install.ps1 -Global -Doctor

# Por proyecto (local): vive en <proyecto>\harness\
.\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,sql

# Global (toda la máquina): ~/.config/opencode\
.\install.ps1 -Global -Skills docker,ui-ux-mockup

# Skills por proyecto sin duplicar las reglas (si ya las instalaste en global)
.\install.ps1 -Project "D:\ruta\al\proyecto" -Skills angular,sql -SkillsOnly

# Volver a instalar las reglas que un -SkillsOnly había desactivado
.\install.ps1 -Project "D:\ruta\al\proyecto" -Update -IncludeRules

# Actualizar lo ya declarado, en su scope (no necesitas recordar cuál)
.\install.ps1 -Update -Project "D:\ruta\al\proyecto"
.\install.ps1 -Update -Global

# Previsualizar sin modificar nada (instalar/refrescar/respaldar/omitir/podar)
.\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,sql -WhatIf

# Actualizar desde otro catálogo (clon local o URL git), sin abrir el repo Harness
.\install.ps1 -Update -Project "D:\ruta\al\proyecto" -Source "https://github.com/TheNefelin/Harness"
```

Qué hace:

1. Copia las **skills elegidas** y las **reglas** (`AGENTS.md`) al destino del scope.
2. Escribe `.harness.json` (`{schemaVersion, scope, rules, skills, harnessVersion}`): la **declaración** que usa `-Update`.
3. Local: crea `opencode.json` si falta y agrega `harness/skills/` a `.gitignore`.
4. **Nunca pisa** skills/reglas ajenas: las **respalda** en `.harness-backup\` y las omite (o las reemplaza con `-Force`).
5. `-Update` alinea el set: agrega las que falten y **poda** las que ya no declaraste.

`-Detect` no instala: escanea el proyecto (marcadores de archivos y dependencias) y compara con el catálogo, listando las tecnologías **sin skill** (candidatas a crear). En una instalación Local, ese reporte se muestra además de forma informativa.

`-WhatIf` previsualiza la operación completa (instalar, refrescar, respaldar, omitir, podar) **sin escribir nada**: úsalo para ver qué pasaría antes de aplicar.

`-Doctor` audita la instalación del scope (manifiesto `.harness.json`, marcadores y hashes de cada skill, reglas y `opencode.json`) y sale con código **0** (ok, con avisos) o **1** (fallo): útil para saber si algo quedó a medias o para CI.

### Detección de tecnologías (`-Detect`)

Es **heurística** (marcadores de archivos y dependencias, no análisis de código) y recorre **todo el árbol** del proyecto, excluyendo `node_modules`, `bin`, `obj`, `.git`, `harness/` y similares. Lee las dependencias de **todos** los paquetes (varios `package.json`/`requirements.txt`/`pyproject.toml` en un monorepo) y **agrega a nivel global** (no separa por subcarpeta). Añade `-Verbose` para ver **la evidencia** de cada tecnología (con la ruta del archivo que la disparó).

| Skill | Marcador |
| --- | --- |
| `dotnet` | `*.csproj` / `*.sln` / `Directory.Packages.props` |
| `godot` | `project.godot` / `*.tscn` / `*.gd` |
| `docker` | `Dockerfile` / `compose.yaml\|yml` / `docker-compose.*` / `.dockerignore` |
| `kubernetes` | `Chart.yaml` / `kustomization.yaml\|yml` o carpetas `k8s` / `kubernetes` / `manifests` / `helm` |
| `github-actions` | `.github/workflows/` |
| `sql` | `*.sql`; o driver en `package.json` (`pg`/`mysql`/`mssql`), Python (`psycopg`/`sqlalchemy`) o `.csproj` (`Npgsql`/`SqlClient`/`EFCore`) |
| `nosql` | driver en `package.json` (`mongodb`/`redis`/cosmos/dynamodb), Python (`pymongo`/`redis`) o `.csproj` |
| `angular` / `astro` | `package.json`: `@angular/core` / `astro` |
| `aws` / `azure` / `oci` | `*.tf` con `provider "aws"` / `"azurerm"` / `"oci"` |
| `react` / `vue` / `svelte` / `django` / `flask` / `terraform` | reconocidos pero **sin skill** en el catálogo → aparecen como **candidatas a crear** |

## Qué queda en cada scope

**Local** (en el proyecto):

```
proyecto/
├─ opencode.json          # apunta a harness/ y define permisos       (commit)
├─ .harness.json          # declaración: scope + skills              (commit)
├─ .gitignore             # ignora harness/skills/ y .harness/       (commit)
├─ README.md              # memoria: descripción, uso, comandos      (commit)
├─ DEVELOPMENT.md         # memoria: arquitectura, decisiones        (commit)
├─ .harness/
│  └─ session.md          # checkpoint de sesión                     (ignorado)
└─ harness/
   ├─ AGENTS.md           # reglas del harness                       (commit)
   └─ skills/             # skills instaladas                        (ignorado)
```

**Global** (fuera del proyecto): `~/.config/opencode/` → `AGENTS.md`, `skills/`, `.harness.json`. No toca el proyecto.

- **Commit**: reglas, declaración y memoria. **Ignorado**: las skills (copias gestionadas; se refrescan con `-Update`) y el checkpoint `.harness/` (estado local de sesión).
- openCode combina **global + proyecto**: puedes mezclar **skills** de ambos scopes, pero las **reglas** (`AGENTS.md`) deben vivir en **un solo** scope. Si ya las tienes en global, instala las skills del proyecto con `-SkillsOnly` (no vuelve a copiar las reglas); para revertirlo, `-Update -IncludeRules` (en Local asegura también `instructions` en `opencode.json`).

## Uso

- Abre openCode **dentro del proyecto** y, tras instalar, **recárgalo con `/reload`** (no cierra la TUI; si no toma los cambios, reinícialo).
- Las **reglas** se cargan automáticamente.
- Las **skills** se activan solas según su `description` (no hay que invocarlas).
- Mantén `DEVELOPMENT.md` al día: es la memoria que evita reexplicar todo.
- En tareas largas, el agente deja el punto de continuación en `.harness/session.md` (local, ignorado por Git); al retomar, lo lee primero.

## Onboarding: app nueva vs. app existente

**App nueva (desde cero)**

1. Instala con tus skills y contexto: `.\install.ps1 -Project "<ruta>" -Skills dotnet,sql -Context`.
2. Rellena `README.md`: qué es, para quién y el alcance del MVP.
3. Rellena `DEVELOPMENT.md` con las primeras decisiones (stack, arquitectura, pendientes).
4. Avanza en pasos pequeños; al cerrar cada paso, actualiza `DEVELOPMENT.md`.

**App existente (ya en marcha)**

1. Instala con tus skills y `-Context`: las plantillas solo se crean si **no** existen, nunca pisan tus archivos.
2. Conserva tu `README.md`; crea o actualiza `DEVELOPMENT.md` con arquitectura, comandos de build/test, decisiones y pendientes.
3. Revisa que `opencode.json` apunte a `harness/` y ajusta permisos si hace falta.

En ambos casos el agente lee primero `AGENTS.md` + `DEVELOPMENT.md`: cuanto mejor sea ese contexto, menos tokens gastas repitiendo.

**Colaborador (clon nuevo)**

1. Las skills instaladas viven en `harness/skills/` y están **ignoradas por git** (son artefactos), así que un clon nuevo **no** las trae.
2. Tras clonar, ejecuta `.\install.ps1 -Update` (lee `.harness.json`, que **sí** se versiona) para materializar las skills declaradas.
3. Si no existiera `.harness.json`, instala con `-Skills` según el stack del proyecto.

## Actualizar

`.\install.ps1 -Update` (con `-Project` o `-Global`) refresca las skills y reglas declaradas, en su scope, sin que tengas que recordar cuál. Alinea el set (agrega y poda) y respalda lo que reemplace.

Por defecto usa el catálogo **junto al script**. Para actualizar **desde otra ubicación** (un clon propio o el repo remoto) sin abrir el Harness, indica el origen con `-Source` (ruta local o URL git):

```powershell
.\install.ps1 -Update -Project "D:\ruta\al\proyecto" -Source "D:\ruta\al\Harness"
.\install.ps1 -Update -Global -Source "https://github.com/TheNefelin/Harness"
```

La instalación **no guarda la ruta del repo**: el marcador de cada skill solo tiene `version` y `hash`, y ni `.harness.json` ni `opencode.json` contienen rutas absolutas. Por eso **mover o clonar el repo no rompe nada**: la instalación sigue válida y `-Update` corre desde la **nueva** ubicación del script (o con `-Source "<ruta nueva>"`). **No hay que reinstalar.**

Para cambiar el set, pasa `-Skills` de nuevo:

```powershell
.\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,sql,nosql
```

## Catálogo, instalación y personalizaciones

Tres capas separadas, para poder mejorar el Harness sin perder tus cambios:

1. **Catálogo** — las versiones oficiales en el repositorio Harness (o el que indiques con `-Source`). Es la fuente de verdad.
2. **Instalación** — las copias que openCode usa en cada proyecto (`<proyecto>\harness\skills\`) o global (`~/.config/opencode\skills\`). Son **artefactos gestionados**: no los edites a mano; se regeneran con `-Update`.
3. **Personalizaciones** — todo lo que no lleva el marcador `.harness-source`. El instalador **nunca** lo poda ni lo pisa; tu propia skill o tus notas viven aquí.

**Política ante diferencias/conflictos** (sin pérdida de datos):

- Al actualizar, si una skill instalada está **idéntica** al catálogo → no hace nada (`sin cambios`).
- Si **no existe** → la instala.
- Si la **editaste a mano** (la copia difiere de la que se instaló) → **la respalda** en `.harness-backup\` y avisa `CONFLICT` antes de refrescar.
- Si es **ajena** (sin marcador) → la omite, salvo `-Force` (que la respalda y reemplaza).
- `-WhatIf` muestra todo esto **antes** de tocar nada.

Las actualizaciones son **seguras**: primero preparan la copia en un directorio temporal y la validan; recién entonces reemplazan. Si algo falla, restauran el respaldo automáticamente (**rollback**). Nunca queda una skill a medias.

## Verificación (CI)

El catálogo se autoverifica con un script **determinista**, sin depender de openCode: sirve en local y en CI.

```powershell
.\tools\check.ps1            # estructura, referencias, triggers, evals y frescura
.\tools\check.ps1 -Strict    # los avisos también cuentan como fallo
.\tools\check.ps1 -MaxAgeDays 120 -OverlapThreshold 0.4
```

Comprueba cinco cosas sobre `skills/`:

1. **Estructura** — cada `SKILL.md` tiene frontmatter, `name` igual a su carpeta, `description` presente y acotada, y cuerpo ≤ 400 líneas.
2. **Referencias** — cada `references/**.md` está **citado** y es **alcanzable** desde su `SKILL.md` (directamente o encadenando referencias; admite sub-referencias). Evita el *progressive disclosure roto*: referencias que nunca se leen porque ningún archivo las nombra.
3. **Solapamiento de triggers** — cuánto se pisan las `description` (vocabulario distintivo, ignorando el bloque `NO ...`). Avisa si dos skills superan el umbral de Jaccard (`-OverlapThreshold`, **0,5** por defecto; el catálogo actual no pasa de 0,25, así que hay margen ×2).
4. **Evals de disparo (heurísticas de routing)** — casos curados en `evals/triggers.json` (`{id, tipo, prompt, expect}`: `expect` es el nombre de la skill esperada, `"none"` o `null` para negativos). Exige que **gane** la skill esperada, no solo que aparezca. Compara el vocabulario del prompt contra las `description`: **no ejecuta openCode** ni comprueba qué skill activa el agente de verdad, así que mide **regresiones léxicas**, no el routing real. El desglose por `tipo` (positivo/ambiguo/frontera/negativo) sale en el resumen.
5. **Frescura** — antigüedad de los marcadores `verificado YYYY-MM-DD`; **falla** si superan `-MaxAgeDays` (180 por defecto).

Sale con código **0** (ok, con avisos) o **1** (fallo), igual que `install.ps1 -Doctor`. El workflow [`.github/workflows/check.yml`](.github/workflows/check.yml) lo ejecuta en cada push/PR y **una vez al mes** (para detectar drift de frescura aunque no haya commits).

Además, `tools/test.ps1` corre **pruebas de integración** de `install.ps1` y `check.ps1` en un sandbox temporal (instalación local, `-WhatIf`, `-Update` con conflicto y respaldo, `-Detect`, guard de `schemaVersion`, protección de skills ajenas y códigos de salida). Es auto-contenido (sin módulos externos) y el CI lo ejecuta junto al verificador.

```powershell
.\tools\test.ps1              # pruebas de integración
.\tools\test.ps1 -KeepSandbox # conserva el sandbox para inspeccionarlo
```

Al crear o cambiar una skill, añade casos a `evals/triggers.json` (positivo + ambiguo + negativo): es la red que evita que dos skills se disparen a la vez. Ver [CONTRIBUTING](CONTRIBUTING.md) para el detalle.

### Versionado

El repo sigue **SemVer** (`VERSION` + `CHANGELOG.md`): `MAJOR` rompe compatibilidad, `MINOR` añade, `PATCH` corrige.

- Cambiar el **formato** de `.harness.json`, la estructura de una skill o los parámetros de `install.ps1` de forma incompatible → **MAJOR**.
- Añadir skills, opciones o comprobaciones compatibles → **MINOR**.
- Correcciones de contenido (frescura, erratas) → **PATCH**.

El manifiesto lleva `schemaVersion` (hoy `1`). Si el formato cambia, se sube `schemaVersion` y se documenta la migración aquí. Mientras tanto, `install.ps1` **avisa** si el campo falta (formato antiguo) y **aborta** (`-Update`/instalación) si el manifiesto trae un `schemaVersion` más nuevo del soportado, para no corromper una instalación hecha con una versión posterior.

## Alcance (intencional)

Este Harness está **acoplado a openCode** a propósito, no por omisión: se apoya en sus `AGENTS.md`, en el descubrimiento de skills por `description` y en su `opencode.json`. Otros agentes (Claude Code, Codex, Cursor...) usan formatos afines, pero adaptarlos es un trabajo aparte que hoy **no** está en alcance. Un solo target bien soportado es una decisión, no una limitación pendiente.

## Hoja de ruta (diferido)

Estos conceptos existen en harness avanzados, pero **no** se incluyen todavía porque no hay un requisito que los justifique (evitar sobreingeniería):

- **Hands** — conexiones/herramientas que se le dan al agente (servidores MCP o scripts con credenciales). Ejemplos posibles: Brevo (email transaccional), Cloudinary (documentos e imágenes).
- **Hooks** — automatismos vía plugins de openCode. En gran parte cubiertos ya por `permission` (bloquear `.env`, pedir permiso para Git/instalaciones).
- **Agentes** — subagentes de openCode (`.opencode/agents/`). Otra capa con su propio coste de contexto; se evaluará si aporta.

## Créditos

Inspirado en el concepto de *harness* de [ericrisco/rsc-harness](https://github.com/ericrisco/rsc-harness) (reglas, skills, memoria y herramientas para agentes de código). Este repositorio es una implementación propia y más simple; no reutiliza su código.

## Licencia

MIT — ver [LICENSE](LICENSE).
