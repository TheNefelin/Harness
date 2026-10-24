---
name: harness-install
description: "Instalar, actualizar o diagnosticar el Harness (reglas + skills) en un proyecto, para openCode, Codex, Cursor o Cline, clonando el repositorio y ejecutando su instalador. Usar cuando el usuario pida instalar, actualizar, refrescar o diagnosticar el Harness o sus skills. NO para instalar un cliente, crear skills (eso es editar el repositorio) ni revisar la frescura del catálogo ('harness-freshness')."
---

# Harness — Instalación y actualización

> El Harness es un conjunto de reglas (`AGENTS.md`), skills y plantillas de memoria para proyectos de software. Se instala **siempre en local**, dentro de un proyecto, y expone las mismas reglas al cliente que uses: openCode, Codex, Cursor o Cline. Se distribuye como repositorio y se instala con un script; **no** existe instalación por URL.

Repositorio: `https://github.com/TheNefelin/Harness.git`

> **Arranque desde el repo (aún sin instalar):** el procedimiento de abajo asume el repo ya clonado. Para el caso "tengo la URL y quiero instalar", el punto de entrada es `README → Instalación por un agente`.

## Cuándo NO usar

| Situación | Dónde corresponde |
|-----------|-------------------|
| Crear o modificar una skill del catálogo | Editar `skills/<name>/SKILL.md` en el repositorio |
| Instalar un cliente (openCode, Codex, Cursor, Cline) | Documentación de ese cliente |
| Criterios técnicos del proyecto | `SKILL.md` del proyecto (no esta skill) |

## Requisitos

- `git`.
- PowerShell: nativo en Windows; en Linux/macOS usar **PowerShell 7+ (`pwsh`)**. Los scripts son **multiplataforma** (Windows y Linux/macOS); el CI los prueba en ambos.
- Si el target es **openCode**, se requiere **V2** (o superior): la configuración usa la sintaxis V2 (`permissions`/`shell`/`skills`). **V1 rechaza** ese bloque (aborta con `ConfigInvalidError`: la app no carga el config ni las protecciones de `.env`/edición/shell); si el `opencode.json` ya existía en formato V1, `-Doctor` lo avisa — migra a `permissions` (array), `shell` y `skills` (array de directorios) o reinstala con el archivo eliminado.

## Parámetros del instalador

| Parámetro | Descripción |
|-----------|-------------|
| `-List` | Muestra el catálogo (nombre + descripción) y los targets disponibles; sale |
| `-Detect` | Escanea el proyecto (`-Project`, por defecto el directorio actual) y lista las tecnologías sin skill en el catálogo (incluye **Arduino/PlatformIO**: `.ino`, `platformio.ini`, `arduino.json`, `sketch.yaml`). Solo lectura |
| `-Doctor` | Audita la instalación del proyecto: manifiesto, marcadores/hashes, reglas, y **cada target declarado** (config de openCode, punteros de Codex/Cursor/Cline). Comprueba la **versión de openCode V1/V2** si ese target está instalado y la **memoria** (`README.md`/`DEVELOPMENT.md`/`SKILL.md` y checkpoint). Solo lectura; sale 0/1 |
| `-Adopt` | Informe de **solo lectura**: compara tus `README.md`/`DEVELOPMENT.md`/`SKILL.md` con las plantillas e **imprime el diff** (`-` proyecto, `+` plantilla). **Nunca escribe**; es una propuesta. Cubre el `.md` con contenido que no sigue el estándar |
| `-Project <ruta>` | Raíz del proyecto. Si se omite, se usa el directorio actual |
| `-Target <lista>` | Cliente(s): `opencode` (por defecto), `codex`, `cursor`, `cline`, o `all`. Separados por coma |
| `-Skills a,b,c` | Skills a instalar. **Obligatorio** salvo con `-Update`/`-Uninstall`/`-List`: no hay set por defecto |
| `-Update` | Refresca lo declarado en `.harness.json` (skills **y targets**), agrega lo que falte y **poda** lo que ya no se declare. Si el catálogo **retiró** una skill declarada, avisa, la omite y refresca el resto |
| `-Uninstall` | Desinstala **por pertenencia**: retira skills con marcador `.harness-source`, reglas (`rules:true`/hash == catálogo), el `instructions` que el Harness **añadió** y los **punteros** que siguen siendo la plantilla; lo gestionado **se mueve a `.harness-backup`** y lo **ajeno se conserva**. Los directorios solo se borran si quedan vacíos. Admite `-WhatIf` |
| `-WhatIf` | Previsualiza qué haría (instalar/refrescar/respaldar/omitir/podar) sin modificar nada |
| `-Source <ruta\|url>` | Origen del catálogo: clon local o URL git (se clona a temp). Actualiza sin abrir el repo Harness. Valida que sea un catálogo completo (`skills/`, `AGENTS.md`, `templates/` con las plantillas de todos los targets) **antes** de desplegar |
| `-Force` | Reemplaza skills, reglas o punteros ajenos (con respaldo) en vez de omitirlos |
| `-Context` | Copia además las plantillas de memoria (`README.md`, `DEVELOPMENT.md`, `SKILL.md`) y el checkpoint `.harness/session.md` si no existen. Si un `.md` existe **vacío** (0 bytes), se **siembra** la plantilla; con contenido, se respeta. La plantilla de `DEVELOPMENT.md` abre con el **Mapa del proyecto** (índice puntero) |
| `-SkillsOnly` | Instala las skills y **omite las reglas** (`AGENTS.md`). Solo vale con `-Target opencode`: Codex, Cursor y Cline leen un puntero a `harness/AGENTS.md`, así que necesitan las reglas. Incompatible con un target de puntero |
| `-IncludeRules` | **Revierte** un `rules:false` previo (de un `-SkillsOnly`): reinstala las reglas y asegura `instructions` en `opencode.json`. Incompatible con `-SkillsOnly` |
| `-Global`, `-Scope Global` | **Obsoletos**: fallan con un mensaje explícito. El Harness no escribe en `~/.config` ni en el perfil del usuario |

## Procedimiento

1. **Confirmar con el usuario** el **proyecto** (ruta raíz), los **targets** y **qué skills** quiere. Sin `-Skills` la instalación falla: correr `-List` y mostrar el catálogo antes de preguntar.
2. **Clonar** el repositorio en una carpeta temporal (fuera del proyecto).
3. **Ejecutar el instalador** desde el clon:

   ```powershell
   # openCode (target por defecto) en un proyecto
   & "<temp>\Harness\install.ps1" -Project "<ruta del proyecto>" -Skills angular,dotnet,sql -Context

   # Varios clientes a la vez
   & "<temp>\Harness\install.ps1" -Project "<ruta del proyecto>" -Skills angular,dotnet -Target codex,cursor

   # Todos los clientes
   & "<temp>\Harness\install.ps1" -Project "<ruta del proyecto>" -Skills angular,dotnet -Target all

   # Actualizar lo ya declarado (skills y targets)
   & "<temp>\Harness\install.ps1" -Project "<ruta del proyecto>" -Update
   ```

   En Linux/macOS, invocar con `pwsh -File <ruta>/install.ps1 ...`.
4. **Verificar**: existe `<proyecto>\harness\skills\<name>\SKILL.md` por cada skill pedida, `<proyecto>\harness\AGENTS.md` y el `.harness.json` con los targets. Opcional: `-Doctor`.
5. **Eliminar el clon temporal.**
6. **Reportar** e indicar al usuario **recargar el cliente** (openCode: `/reload`) para que cargue reglas y skills (no cierra la TUI; si no toma los cambios, reiniciar). No ejecutar Git (§9).

## Actualizar: agregar o quitar skills o targets

El set vive en `.harness.json`. Para **cambiarlo**, re-ejecuta con `-Skills` indicando el set **completo** (lo declarado + la nueva); `-Update` alinea (agrega y poda). Los targets se cambian con `-Target`; `-Update` sin `-Target` refresca los declarados.

```powershell
# De {dotnet,sql} a {dotnet,sql,nosql}
& "<temp>\Harness\install.ps1" -Project "<ruta>" -Update -Skills dotnet,sql,nosql

# Agregar Cursor a una instalacion que ya tenia openCode
& "<temp>\Harness\install.ps1" -Project "<ruta>" -Update -Target opencode,cursor
```

Una skill gestionada que sale del set se **poda** y se respalda en `.harness-backup\`.

## Qué instala y dónde

**Fuente única:** `harness/AGENTS.md`. Nunca se duplica el contenido entre clientes.

| Target | Archivo que consume el cliente | Qué escribe el Harness |
|--------|--------------------------------|------------------------|
| `opencode` | `opencode.json` | Config completa (permisos V2 + `skills` + `instructions -> harness/AGENTS.md`); si ya existía, **fusiona** `instructions` y no pisa el resto |
| `codex` | `AGENTS.md` (raíz) | Puntero corto que remite a `harness/AGENTS.md` |
| `cursor` | `.cursor/rules/harness.mdc` | Puntero con frontmatter `alwaysApply: true` que remite a `harness/AGENTS.md` |
| `cline` | `.clinerules/harness.md` | Puntero que remite a `harness/AGENTS.md` |

- En **todos** los casos se instala `harness/AGENTS.md` y `harness/skills/`. El `.gitignore` ignora `harness/skills/`, `harness/.harness-backup/` y `.harness/`; los punteros y `opencode.json` **no** se ignoran (son configuración del proyecto).
- `opencode.json` apunta a `harness/skills` por la clave `skills` (array de directorios, formato V2); abrir openCode **en la raíz** del proyecto (las rutas son relativas al directorio de trabajo).
- Los **permisos** que se instalan dejan Git **denegado por defecto** (`git *` → `deny`) y solo permiten la lectura (`status`, `log`, `diff`, `show`, `ls-files`, `ls-tree`, `rev-parse`, `blame`, `grep`, `check-ignore`, `remote -v` y los listados). Si un comando Git aparece bloqueado, es **deliberado**: no lo sortees (§9).
- El instalador **nunca pisa** skills, reglas ni punteros ajenos: los respalda en `.harness-backup\` y los omite, salvo `-Force`.
- Tres capas: **catálogo** (repo Harness o `-Source`), **instalación** (copias gestionadas con marcador `.harness-source`; no editar a mano) y **personalizaciones** (sin marcador; nunca se podan).
- El **checkpoint de sesión** (`.harness/session.md`) es estado local y efímero (fuera de Git): el punto de continuación de una tarea larga. La memoria durable sigue siendo `DEVELOPMENT.md`, que abre con el **Mapa del proyecto** (área → dónde mirar → cuándo): el agente lee la fila del área y abre solo ese destino.
- **`-Uninstall` no destruye**: lo gestionado se mueve a `.harness-backup\` y lo ajeno se conserva; un puntero editado por el usuario se conserva. Mientras queden respaldos, el `.gitignore` conserva la línea `harness/.harness-backup/` y el cierre avisa de cómo retirarla cuando los borres.
- **Conflictos:** al actualizar, una skill idéntica al catálogo no se toca (`sin cambios`); una **editada localmente** se **respalda** y se avisa `CONFLICT` antes de refrescar. Sin pérdida de datos.

## Anti-patrones / gotchas

| Anti-patrón | Problema | Correcto |
|-------------|----------|----------|
| Buscar una "instalación por URL" | El script lee las skills de la copia local | Clonar el repo y correr `install.ps1` |
| Instalar sin `-Skills` | No hay set por defecto; el script falla | Definir el set con el usuario, tras `-List` |
| Abrir openCode fuera de la raíz | `skills` es relativo al CWD | Abrir openCode en la raíz del proyecto |
| Copiar `harness/skills` a mano | Se desincroniza de `-Update` | Usar el instalador |
| Usar `-Global` o `-Scope Global` | El scope global se eliminó; el comando falla | Instalar en el proyecto con `-Project` |
| Editar `harness/AGENTS.md` a mano | Se pierde en el siguiente `-Update` | Proponer el cambio; el usuario decide (el archivo se respalda) |
| Duplicar las reglas en cada cliente | Deriva: cuatro copias que se contradicen | Punteros a `harness/AGENTS.md` |
| `-SkillsOnly` con `-Target codex` | El puntero apuntaría a un `AGENTS.md` que no se instaló | `-SkillsOnly` solo con `opencode`, o quitar `-SkillsOnly` |
| Tras `-SkillsOnly`, correr `-Update` esperando recuperar las reglas | `-Update` respeta el `rules:false` del manifiesto | Usar `-Update -IncludeRules` |
| Mover o clonar el repo y reinstalar | La instalación no guarda la ruta del repo; no hay nada roto | Seguir usándola; refrescar con `-Update` desde la nueva ubicación |
| Al agregar, pasar a `-Skills` solo la skill nueva | El set se **poda**: pierdes las demás | Pasar el **set completo** (actual + nueva) |

## Checklist

- [ ] Proyecto, targets y skills confirmados con el usuario
- [ ] Skills elegidas explícitamente (no vacío)
- [ ] Repositorio clonado en carpeta temporal
- [ ] `install.ps1` ejecutado con el intérprete correcto
- [ ] Por cada skill: `<proyecto>\harness\skills\<name>\SKILL.md`
- [ ] `harness/AGENTS.md` presente y, por cada target, su archivo (config o puntero)
- [ ] `.harness.json` escrito con `targets` y `skills`
- [ ] Memoria sembrada con `-Context` si el usuario lo pidió
- [ ] Clon temporal eliminado
- [ ] Sin commit/push; usuario avisado de recargar (`/reload`) o reiniciar el cliente
