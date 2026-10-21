---
name: harness-install
description: Instalar, actualizar o diagnosticar el Harness (reglas + skills de openCode), local o global, clonando el repositorio y ejecutando su instalador. Usar cuando el usuario pida instalar, actualizar, refrescar o diagnosticar el Harness o sus skills. NO para instalar openCode, crear skills (eso es editar el repositorio) ni revisar la frescura del catálogo ('harness-freshness').
---

# Harness — Instalación y actualización

> El Harness es un conjunto de reglas (`AGENTS.md`), skills y plantillas de memoria para openCode. Se distribuye como repositorio y se instala con un script; **no** existe instalación por URL.

Repositorio: `https://github.com/TheNefelin/Harness.git`

> **Arranque desde el repo (aún sin instalar):** el procedimiento de abajo asume el repo ya clonado. Para el caso "tengo la URL y quiero instalar", el punto de entrada es `README → Instalación por un agente`.

## Cuándo NO usar

| Situación | Dónde corresponde |
|-----------|-------------------|
| Crear o modificar una skill del catálogo | Editar `skills/<name>/SKILL.md` en el repositorio |
| Instalar openCode en la máquina | Documentación de openCode |
| Criterios técnicos del proyecto | `SKILL.md` del proyecto (no esta skill) |

## Requisitos

- `git`.
- PowerShell: nativo en Windows; en Linux/macOS usar **PowerShell 7+ (`pwsh`)**. Los scripts son **multiplataforma** (Windows y Linux/macOS); el CI los prueba en ambos.
- **openCode V2** (o superior): la configuración usa la sintaxis V2 (`permissions`/`shell`/`skills`). **openCode V1 rechaza** ese bloque (aborta con `ConfigInvalidError`: la app no carga el config ni las protecciones de `.env`/edición/shell); si el `opencode.json` ya existía en formato V1, `-Doctor` lo avisa — migra a `permissions` (array), `shell` y `skills` (array de directorios) o reinstala con el archivo eliminado.

## Parámetros del instalador

| Parámetro | Descripción |
|-----------|-------------|
| `-List` | Muestra el catálogo (nombre + descripción) y sale |
| `-Detect` | Escanea el proyecto (`-Project`) y lista las tecnologías sin skill en el catálogo. Solo lectura |
| `-Doctor` | Audita la instalación del scope (manifiesto, marcadores/hashes, reglas, `opencode.json`, **versión del cliente V1/V2**). Solo lectura; sale 0/1 |
| `-Project <ruta>` | Scope **Local**: vive en `<ruta>\harness\` |
| `-Global` | Scope **Global**: vive en `~/.config/opencode\` |
| `-Skills a,b,c` | Skills a instalar. **Obligatorio** salvo con `-Update`/`-Uninstall`/`-List`: no hay set por defecto |
| `-Update` | Refresca lo declarado en `.harness.json` (su scope), agrega lo que falte y **poda** lo que ya no se declare |
| `-Uninstall` | Desinstala el Harness del scope **por pertenencia**: retira skills con marcador `.harness-source`, reglas (`rules:true`/hash == catálogo) y el `instructions` que el Harness **añadió**; lo gestionado **se mueve a `.harness-backup`** y lo **ajeno se conserva** (skills sin marcador, archivos propios, config/plugins de `~/.config/opencode`). Los directorios solo se borran si quedan vacíos. Admite `-WhatIf` |
| `-WhatIf` | Previsualiza qué haría (instalar/refrescar/respaldar/omitir/podar) sin modificar nada |
| `-Source <ruta\|url>` | Origen del catálogo: clon local o URL git (se clona a temp). Actualiza sin abrir el repo Harness. Valida que sea un catálogo completo (`skills/`, `AGENTS.md`, `templates/opencode*.json`) **antes** de desplegar |
| `-Force` | Reemplaza skills/reglas ajenas (con respaldo) en vez de omitirlas |
| `-Context` | Local: copia además las plantillas de memoria (`README.md`, `DEVELOPMENT.md`, `SKILL.md`) y el checkpoint `.harness/session.md` si no existen. Si un `.md` existe **vacío** (0 bytes), se **siembra** la plantilla; con contenido, se respeta. La plantilla de `DEVELOPMENT.md` abre con el **Mapa del proyecto** (índice puntero) |
| `-SkillsOnly` | Instala las skills y **omite las reglas** (`AGENTS.md`) en ese scope: úsalo si las reglas ya viven en el otro scope (p. ej. global), para no cargar dos copias idénticas |
| `-IncludeRules` | **Revierte** un `rules:false` previo (de un `-SkillsOnly`): reinstala las reglas y, en Local, asegura `instructions` en `opencode.json`. Incompatible con `-SkillsOnly` |

## Procedimiento

1. **Confirmar con el usuario** el **scope** (Local de un proyecto o Global de la máquina) y **qué skills** quiere. Sin `-Skills` la instalación falla: correr `-List` y mostrar el catálogo antes de preguntar.
2. **Clonar** el repositorio en una carpeta temporal (fuera del proyecto).
3. **Ejecutar el instalador** desde el clon:

   ```powershell
   # Local (un proyecto)
   & "<temp>\Harness\install.ps1" -Project "<ruta del proyecto>" -Skills angular,dotnet,sql -Context

   # Global (toda la máquina)
   & "<temp>\Harness\install.ps1" -Global -Skills docker,kubernetes

   # Actualizar lo ya declarado
   & "<temp>\Harness\install.ps1" -Update -Project "<ruta del proyecto>"
   ```

   En Linux/macOS, invocar con `pwsh -File <ruta>/install.ps1 ...`.
4. **Verificar**: existe `<scope root>\skills\<name>\SKILL.md` por cada skill pedida y quedo escrito el `.harness.json`. Opcional: `-Doctor` para auditar (manifiesto, rutas, reglas, config).
5. **Eliminar el clon temporal.**
6. **Reportar** e indicar al usuario **recargar openCode** con `/reload` para que cargue reglas y skills (no cierra la TUI; si no toma los cambios, reiniciar). No ejecutar Git (§9).

## Actualizar: agregar o quitar skills

El set vive en `.harness.json`. Para **cambiarlo**, re-ejecuta con `-Skills` indicando el set **completo** (lo declarado + la nueva); `-Update` alinea (agrega y poda):

```powershell
# De {dotnet,sql} a {dotnet,sql,nosql}
& "<temp>\Harness\install.ps1" -Update -Project "<ruta>" -Skills dotnet,sql,nosql
```

`-Update` **sin** `-Skills` solo refresca el set actual (no agrega ni quita). Una skill gestionada que sale del set se **poda** y se respalda en `.harness-backup\`.

## Qué instala y dónde

| Scope | Destino | Contenido |
|-------|---------|-----------|
| Local | `<proyecto>\` | `harness\AGENTS.md`, `harness\skills\`, `opencode.json`, `.harness.json`, `.gitignore` (ignora `harness/skills/` y `.harness/`); con `-Context`, además `README.md`, `DEVELOPMENT.md`, `SKILL.md` y `.harness\session.md` |
| Global | `~/.config/opencode\` | `AGENTS.md`, `skills\`, `opencode.json` (permisos), `.harness.json` |

- En Local, `opencode.json` apunta a `harness/skills` por la clave `skills` (array de directorios, formato V2); abrir openCode **en la raíz** del proyecto (las rutas son relativas al directorio de trabajo).
- Las **reglas** (`AGENTS.md`) deben vivir en **un solo** scope. openCode combina global + proyecto, así que instalarlas en ambos carga **dos copias idénticas**: usa `-SkillsOnly` en el scope que solo aporta skills.
- El instalador **nunca pisa** skills/reglas ajenas: las respalda en `.harness-backup\` y las omite, salvo `-Force`.
- Tres capas: **catálogo** (repo Harness o `-Source`), **instalación** (copias gestionadas con marcador `.harness-source`; no editar a mano) y **personalizaciones** (sin marcador; nunca se podan).
- El **checkpoint de sesión** (`.harness/session.md`) es estado local y efímero (fuera de Git): el punto de continuación de una tarea larga. La memoria durable sigue siendo `DEVELOPMENT.md`, que abre con el **Mapa del proyecto** (área → dónde mirar → cuándo): el agente lee la fila del área y abre solo ese destino.
- **`-Uninstall` no destruye**: lo gestionado se mueve a `.harness-backup\` y lo ajeno se conserva. En **Global** `~/.config/opencode\` **no se borra** (tiene tu config, plugins y otros agentes); solo se retiran las skills/reglas gestionadas. Mientras queden respaldos, el `.gitignore` conserva la línea `harness/.harness-backup/` y el cierre avisa de cómo retirarla cuando los borres.
- **Conflictos:** al actualizar, una skill idéntica al catálogo no se toca (`sin cambios`); una **editada localmente** se **respalda** y se avisa `CONFLICT` antes de refrescar. Sin pérdida de datos.

## Anti-patrones / gotchas

| Anti-patrón | Problema | Correcto |
|-------------|----------|----------|
| Buscar una "instalación por URL" | El script lee las skills de la copia local | Clonar el repo y correr `install.ps1` |
| Instalar sin `-Skills` | No hay set por defecto; el script falla | Definir el set con el usuario, tras `-List` |
| Abrir openCode fuera de la raíz (Local) | `skills` es relativo al CWD | Abrir openCode en la raíz del proyecto |
| Copiar `harness/skills` a mano | Se desincroniza de `-Update` | Usar el instalador |
| Correr `-Global` sin confirmar | Agrega reglas a **todas** las sesiones | Confirmar el scope con el usuario |
| Instalar reglas en global **y** local | openCode combina ambos scopes: las reglas idénticas se cargan dos veces | Reglas en **un solo** scope; en el otro, `-SkillsOnly` |
| Tras `-SkillsOnly`, correr `-Update` esperando recuperar las reglas | `-Update` respeta el `rules:false` del manifiesto | Usar `-Update -IncludeRules` |
| Mover o clonar el repo y reinstalar | La instalación no guarda la ruta del repo; no hay nada roto | Seguir usándola; refrescar con `-Update` desde la nueva ubicación |
| Al agregar, pasar a `-Skills` solo la skill nueva | El set se **poda**: pierdes las demás | Pasar el **set completo** (actual + nueva) |

## Checklist

- [ ] Scope confirmado con el usuario (Local vs Global)
- [ ] Skills elegidas explícitamente (no vacío)
- [ ] Repositorio clonado en carpeta temporal
- [ ] `install.ps1` ejecutado con el intérprete correcto
- [ ] `<scope root>\skills\<name>\SKILL.md` verificado por skill
- [ ] `.harness.json` escrito
- [ ] Clon temporal eliminado
- [ ] Sin commit/push; usuario avisado de recargar (`/reload`) o reiniciar openCode
