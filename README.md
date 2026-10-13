# Harness

Conjunto reutilizable de **reglas**, **skills** y **plantillas de contexto** para desarrollar proyectos con [openCode](https://opencode.ai). Se instala **dentro de cada proyecto** para mantener contexto entre sesiones y ahorrar tokens.

## Qué resuelve

- El agente no improvisa: reglas claras en `AGENTS.md`.
- Las skills se cargan **solo cuando hacen falta** → menos tokens por sesión.
- El contexto del proyecto persiste entre sesiones (`README` / `DEVELOPMENT` / `SKILL`).
- Cada proyecto es **autocontenido**: el harness viaja con el repositorio.

## Estructura

```
Harness/
├─ README.md              # este archivo
├─ LICENSE                # MIT
├─ AGENTS.md              # reglas        ┐
├─ skills/                # 8 skills      ├─ lo que se instala en cada proyecto
├─ templates/
│  ├─ opencode.json       # config del proyecto (skills + permisos)
│  ├─ README.md           # ┐
│  ├─ DEVELOPMENT.md      # ├─ plantillas de contexto (memoria)
│  └─ SKILL.md            # ┘
└─ install.ps1            # instalador
```

## Requisitos

- [openCode](https://opencode.ai) instalado.
- PowerShell (Windows) para `install.ps1`.

## Instalación en un proyecto

```powershell
# Instala reglas + skills + opencode.json
.\install.ps1 -Project "D:\ruta\al\proyecto"

# Además, crea las plantillas de contexto (README/DEVELOPMENT/SKILL)
.\install.ps1 -Project "D:\ruta\al\proyecto" -Context
```

Qué hace:

1. Copia `AGENTS.md` y `skills/` a `<proyecto>\harness\`.
2. Crea `<proyecto>\opencode.json` desde la plantilla (solo si no existe; no pisa nada).
3. Con `-Context`, copia las plantillas de contexto (solo si no existen).
4. Reporta qué creó y qué omitió.

Instalación manual (equivalente):

1. Copia `AGENTS.md` y `skills/` a `<proyecto>\harness\`.
2. Copia `templates\opencode.json` a `<proyecto>\opencode.json`.

## Qué queda en el proyecto

```
proyecto/
├─ opencode.json          # apunta a harness/ y define permisos
├─ AGENTS.md              # (opcional) reglas propias del proyecto
├─ README.md              # contexto: descripción, uso, comandos
├─ DEVELOPMENT.md         # contexto: arquitectura, decisiones, pendientes
└─ harness/
   ├─ AGENTS.md           # reglas del harness
   └─ skills/             # skills reutilizables
```

## Uso

- Abre openCode **dentro del proyecto** y reinícialo tras instalar.
- Las **reglas** se cargan automáticamente.
- Las **skills** se activan solas según su `description` (no hay que invocarlas).
- Mantén `DEVELOPMENT.md` al día: es la memoria que evita reexplicar todo.

## Actualizar el harness en un proyecto

Re-ejecuta el instalador: sobrescribe `harness\AGENTS.md` y `harness\skills\`, y **no toca** `opencode.json` ni tus archivos de contexto.

## Hoja de ruta (diferido)

Estos conceptos existen en harness avanzados, pero **no** se incluyen todavía porque no hay un requisito que los justifique (evitar sobreingeniería):

- **Hands** — conexiones/herramientas que se le dan al agente (servidores MCP o scripts con credenciales). Ejemplos posibles: Brevo (email transaccional), Cloudinary (documentos e imágenes).
- **Hooks** — automatismos vía plugins de openCode. En gran parte cubiertos ya por `permission` (bloquear `.env`, pedir permiso para Git/instalaciones).

## Créditos

Inspirado en el concepto de *harness* de [ericrisco/rsc-harness](https://github.com/ericrisco/rsc-harness) (reglas, skills, memoria y herramientas para agentes de código). Este repositorio es una implementación propia y más simple; no reutiliza su código.

## Licencia

MIT — ver [LICENSE](LICENSE).
