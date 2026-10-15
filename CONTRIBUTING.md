# Contribuir

Gracias por mejorar el Harness. Es un repo de **reglas + skills + herramientas** para openCode; la calidad se mide con `tools/check.ps1`, que debe pasar antes de cualquier PR.

## Principios

1. **Anti-sobreingeniería.** Si no hay un requisito que lo justifique, no se añade. Ver *Hoja de ruta (diferido)* en el README.
2. **Determinismo.** El catálogo se verifica sin depender de openCode: `tools/check.ps1` es la fuente de verdad.
3. **Trazabilidad.** Cada skill declara su alcance (`NO para`), su frescura y sus casos de disparo.

## Antes de abrir un PR

```powershell
.\tools\check.ps1 -Strict
.\tools\test.ps1
```

Si alguno sale distinto de `0`, el PR no es aceptable. El CI ejecuta lo mismo (`.github/workflows/check.yml`). `tools/test.ps1` son pruebas de integración de `install.ps1`/`check.ps1` (auto-contenidas, en un sandbox temporal).

## Añadir una skill

1. **Crea `skills/<nombre>/SKILL.md`** con el frontmatter mínimo:

   ```markdown
   ---
   name: <nombre>
   description: <qué resuelve>. Usar al <disparadores concretos>. NO para <lo que NO cubre> ('otra-skill').
   ---
   ```

   - `name` **debe** coincidir exactamente con el nombre de la carpeta.
   - La `description` hace que la skill se **dispare sola**: empieza por el resultado, lista los disparadores ("Usar al...") y cierra con el bloque `NO para ... ('otra-skill')` para desambiguar de las vecinas.
   - Si la `description` contiene `: ` (dos puntos + espacio) o ` #`, **cítala con comillas dobles** (`description: "..."`); sin citar, YAML la rompe (GitHub y los parsers estrictos fallan). `check.ps1` lo detecta.
   - Cuerpo ≤ **400 líneas**. El detalle largo va en `references/*.md` (progressive disclosure).

2. **Contenido**: decisiones y anti-patrones, no tutoriales. Español neutro y **tuteo** (nada de voseo).

3. **Frescura**: si la skill tiene datos que cambian (versiones, límites, precios, fechas), añade el marcador tras el título (vale en `SKILL.md` y en `references/*.md`):

   ```markdown
   > **Frescura (verificado YYYY-MM-DD):** <claim>. Fuente: <enlace>.
   ```

4. **Evals**: añade casos a `evals/triggers.json` (ver abajo), incluidos 1 ambiguo y 1 negativo.

5. **Verifica**: `.\tools\check.ps1 -Strict`.

## Rúbrica de una skill

Toda skill del catálogo se evalúa con esta rúbrica. Distingue lo **universal** (obligatorio en todas) de lo **condicional** (depende del tipo de skill).

| Aspecto | ¿Aplica a todas? | Qué se exige |
| --- | --- | --- |
| Frontmatter | Universal | `name` == carpeta y `description` válida. Lo valida `check.ps1`. |
| Description (qué/cuándo/NO) | Universal | Empieza por el resultado, lista disparadores ("Usar al...") y cierra con `NO para ... ('<vecina>')`. |
| Delimitación de alcance | Universal | Sección que excluye lo que cubren las skills vecinas. |
| Contenido accionable | Universal | Decisiones y anti-patrones, no tutoriales. |
| Anti-patrones | Universal | Al menos una sección de errores comunes; específicos para IA (p. ej. "afirmar sin verificar"). |
| Honestidad sobre límites | Universal | Lo que la skill no puede verificar se declara; nada de resultados inventados. |
| Longitud | Universal | Cuerpo ≤ 400 líneas. Lo valida `check.ps1`. |
| Progressive disclosure | Condicional | `references/*.md` cuando la skill es larga (roza 400) o ramificada. Una guía secuencial y corta va autocontenida. |
| Marcador de frescura | Condicional | Solo si hay datos que cambian (versiones, límites, precios, fechas). Las de método/principios no lo llevan. |

Los "universal" son obligatorios; los "condicional" se juzgan caso a caso, no se fuerzan. Si dos skills se solapan, la rúbrica no basta: se ajustan las `description` (ver abajo).

## Evals de disparo

`evals/triggers.json` es la red que evita que dos skills se disparen a la vez. Cada caso exige que **gane** la skill esperada (no solo que aparezca). Formato:

```json
{ "id": "<skill>-<tipo>-NN", "tipo": "positivo", "prompt": "...", "expect": "<skill>", "nota": "opcional" }
```

- `id`: identificador único y legible (para citar en un fallo de CI).
- `tipo`: `positivo`, `ambiguo`, `frontera` o `negativo` (informativo; `check.ps1` lo usa para el desglose).
- `expect`: el nombre de la skill esperada, `"none"` o `null` (ninguna debe activarse).

Al añadir una skill, incluye **al menos**:

- **1 positivo claro** — el prompt obvio que debe activarla.
- **1 ambiguo** — un prompt que podría encajar en dos skills y debe ganar esta. Si no sabes cuál debería ganar, las `description` se solapan demasiado: ajústalas antes.
- **1 negativo** — un prompt que **no** debe activar ninguna del catálogo (`expect: null`).
- **1 de frontera** (recomendado) — un prompt que *tienta* a una skill vecina pero debe ganar esta (`expect: <esta>`); cubre el caso "activa la skill equivocada".

## Solapamiento de triggers

`check.ps1` mide la similitud **Jaccard** entre las `description` (vocabulario distintivo, ignorando el bloque `NO ...`). Si dos skills superan el umbral (`-OverlapThreshold`, **0,5** por defecto), hay aviso; con `-Strict`, el PR no pasa. El reporte muestra el par, los términos que comparten y la acción sugerida.

Si te salta:

1. Mira el par y los términos compartidos que reporta `check.ps1`.
2. Decide cuál de las dos es más específica.
3. Amplía su bloque `NO ...` para excluir el caso de la otra, o afina sus términos.
3. Si el solapamiento es **legítimo** (skills complementarias), discútelo antes de tocar el umbral.

## Frescura

Cada marcador `verificado YYYY-MM-DD` cuenta. `check.ps1` **falla** si supera `-MaxAgeDays` (180 por defecto) y **avisa** si hay un marcador de frescura sin fecha. Los avisos **no se silencian**: o se revisa la skill y se actualiza la fecha, o se justifica por qué sigue vigente.

## Cambiar una skill existente

- Revisa que la `description` siga describiendo el alcance real; si tocas los disparadores, actualiza las evals.
- Si cambias un dato del mundo real, actualiza su **fecha de frescura**.
- Las skills instaladas son **artefactos**: no las edites en el proyecto, edítalas aquí.

## Cambios en `install.ps1`, `tools/check.ps1` o `tools/test.ps1`

- `.\tools\check.ps1 -Strict` y `.\tools\test.ps1` en verde.
- Si tocas `install.ps1` (o su comportamiento), añade o ajusta una prueba en `tools/test.ps1`.
- Actualiza `CHANGELOG.md` (y `VERSION` según SemVer).
- Si cambia el formato de `.harness.json` de forma incompatible, sube `schemaVersion` y documenta la migración.

## Checklist del PR

- [ ] `.\tools\check.ps1 -Strict` y `.\tools\test.ps1` en verde (0 fallos; los avisos, resueltos o justificados).
- [ ] `name` == carpeta y `description` con bloque `NO para ...`.
- [ ] Cumple la **rúbrica**: anti-patrones, honestidad sobre límites y (si aplica) `references/` y frescura.
- [ ] La `description` no solapa con otra skill (Jaccard ≤ 0,5).
- [ ] Cuerpo ≤ 400 líneas; el detalle, en `references/`.
- [ ] Español neutro y **tuteo** (sin voseo).
- [ ] Fechas de frescura actualizadas donde corresponda.
- [ ] Evals (positivo + ambiguo + negativo) en `evals/triggers.json`.
- [ ] `CHANGELOG.md` y `VERSION` según SemVer (ver README → Versionado).

## Convenciones

- **Sin dependencias de runtime**: los scripts son PowerShell sin módulos externos.
- **Encoding**: UTF-8 **sin BOM**, saltos **LF**. Los `.ps1` son **ASCII** (sin acentos, por compatibilidad con Windows PowerShell 5.1). `.gitattributes` fuerza `eol=lf`.
- **Commits**: `tipo(scope): resumen en imperativo` + lista de archivos + verificación.

## Alcance

El Harness es para **openCode** (ver README → Alcance). No lo acoplamos a otros agentes ni añadimos dependencias sin una razón concreta.
