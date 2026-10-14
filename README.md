# Harness

Conjunto reutilizable de **reglas**, **skills** y **plantillas de contexto** para desarrollar proyectos con [openCode](https://opencode.ai). Se instala **global** (una vez para toda la máquina) o **por proyecto**, según elijas.

## Qué resuelve

- El agente no improvisa: reglas claras en `AGENTS.md`.
- Las skills se cargan **solo cuando hacen falta** → menos tokens por sesión. Dentro de una skill, el detalle vive en `references/*.md` y se lee **bajo demanda** (progressive disclosure).
- El contexto del proyecto persiste entre sesiones (`README` / `DEVELOPMENT` / `SKILL`).
- Vos elegís el alcance: **global** (cero drift) o **por proyecto** (solo lo necesario).

## Estructura

```
Harness/
├─ README.md              # este archivo
├─ LICENSE                # MIT
├─ VERSION                # versión del harness
├─ AGENTS.md              # reglas        ┐
├─ skills/                # 10 skills     ├─ lo que se instala (global o por proyecto)
├─ templates/
│  ├─ opencode.json       # config del proyecto (instructions + skills.paths + permisos)
│  ├─ README.md           # ┐
│  ├─ DEVELOPMENT.md      # ├─ plantillas de memoria (contexto)
│  └─ SKILL.md            # ┘
└─ install.ps1            # instalador / actualizador
```

## Requisitos

- [openCode](https://opencode.ai) instalado.
- PowerShell (Windows) para `install.ps1`.

## Instalación

Es **agnóstico**: no hay set por defecto. Siempre indicás **qué** skills y **dónde**.

```powershell
# Catálogo disponible (nombre + descripción)
.\install.ps1 -List

# Por proyecto (local): vive en <proyecto>\harness\
.\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,sql

# Global (toda la máquina): ~/.config/opencode\
.\install.ps1 -Global -Skills git,ui-ux-mockup

# Actualizar lo ya declarado, en su scope (no necesitás recordar cuál)
.\install.ps1 -Update -Project "D:\ruta\al\proyecto"
.\install.ps1 -Update -Global
```

Qué hace:

1. Copia las **skills elegidas** y las **reglas** (`AGENTS.md`) al destino del scope.
2. Escribe `.harness.json` (`{scope, rules, skills, harnessVersion}`): la **declaración** que usa `-Update`.
3. Local: crea `opencode.json` si falta y agrega `harness/skills/` a `.gitignore`.
4. **Nunca pisa** skills/reglas ajenas: las **respalda** en `.harness-backup\` y las omite (o las reemplaza con `-Force`).
5. `-Update` alinea el set: agrega las que falten y **poda** las que ya no declaraste.

## Qué queda en cada scope

**Local** (en el proyecto):

```
proyecto/
├─ opencode.json          # apunta a harness/ y define permisos       (commit)
├─ .harness.json          # declaración: scope + skills              (commit)
├─ .gitignore             # ignora harness/skills/                   (commit)
├─ README.md              # memoria: descripción, uso, comandos      (commit)
├─ DEVELOPMENT.md         # memoria: arquitectura, decisiones        (commit)
└─ harness/
   ├─ AGENTS.md           # reglas del harness                       (commit)
   └─ skills/             # skills instaladas                        (ignorado)
```

**Global** (fuera del proyecto): `~/.config/opencode/` → `AGENTS.md`, `skills/`, `.harness.json`. No toca el proyecto.

- **Commit**: reglas, declaración y memoria. **Ignorado**: las skills (copias gestionadas; se refrescan con `-Update`).
- openCode combina **global + proyecto**, así que podés mezclar: skills universales globales y de stack por proyecto.

## Uso

- Abre openCode **dentro del proyecto** y reinícialo tras instalar.
- Las **reglas** se cargan automáticamente.
- Las **skills** se activan solas según su `description` (no hay que invocarlas).
- Mantén `DEVELOPMENT.md` al día: es la memoria que evita reexplicar todo.

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

## Actualizar

`.\install.ps1 -Update` (con `-Project` o `-Global`) refresca las skills y reglas declaradas, en su scope, sin que tengas que recordar cuál. Alinea el set (agrega y poda) y respalda lo que reemplace.

Para cambiar el set, pasá `-Skills` de nuevo:

```powershell
.\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,sql,nosql
```

## Hoja de ruta (diferido)

Estos conceptos existen en harness avanzados, pero **no** se incluyen todavía porque no hay un requisito que los justifique (evitar sobreingeniería):

- **Hands** — conexiones/herramientas que se le dan al agente (servidores MCP o scripts con credenciales). Ejemplos posibles: Brevo (email transaccional), Cloudinary (documentos e imágenes).
- **Hooks** — automatismos vía plugins de openCode. En gran parte cubiertos ya por `permission` (bloquear `.env`, pedir permiso para Git/instalaciones).
- **Agentes** — subagentes de openCode (`.opencode/agents/`). Otra capa con su propio coste de contexto; se evaluará si aporta.

## Créditos

Inspirado en el concepto de *harness* de [ericrisco/rsc-harness](https://github.com/ericrisco/rsc-harness) (reglas, skills, memoria y herramientas para agentes de código). Este repositorio es una implementación propia y más simple; no reutiliza su código.

## Licencia

MIT — ver [LICENSE](LICENSE).
