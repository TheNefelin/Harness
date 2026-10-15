# Contribuir

Gracias por mejorar el Harness. Es un repo de **reglas + skills + herramientas** para openCode; la calidad se mide con `tools/check.ps1`, que debe pasar antes de cualquier PR.

## Antes de empezar

```powershell
.\tools\check.ps1
```

Debe salir `RESULTADO: OK`. Si añades una skill o cambias una `description`, añade también sus **evals** (ver abajo).

## Añadir una skill

1. **Crea la carpeta y el frontmatter** en `skills/<nombre>/SKILL.md`:

   ```markdown
   ---
   name: <nombre>
   description: <qué resuelve>. Usar al <disparadores concretos>. NO para <lo que NO cubre> ('otra-skill').
   ---
   ```

   - `name` **debe** coincidir con el nombre de la carpeta.
   - La `description` es lo que hace que la skill se **dispare sola**: empieza por el resultado, lista los disparadores ("Usar al...") y cierra con el bloque `NO para ... ('otra-skill')` para desambiguar de las vecinas.
   - Cuerpo ≤ **400 líneas**. El detalle largo va en `references/*.md` (progressive disclosure).

2. **Contenido**: decisiones y anti-patrones, no tutoriales. Español neutro y **tuteo** (nada de voseo).

3. **Frescura**: si la skill tiene datos que cambian (versiones, límites, precios, fechas), añade el bloque tras el título:

   ```markdown
   > **Frescura (verificado YYYY-MM-DD):** <claim>. Fuente: <enlace>.
   ```

4. **Evals**: añade casos a `evals/triggers.json` (`{ "prompt": "...", "expect": "<nombre>" }`), incluidos 1-2 de los límites `NO para` que la distinguen de sus vecinas.

5. **Verifica**: `.\tools\check.ps1`.

## Cambiar una skill existente

- Revisa que la `description` siga describiendo el alcance real; si tocas los disparadores, actualiza las evals.
- Si cambias un dato del mundo real, actualiza también su **fecha de frescura**.
- Las skills instaladas son **artefactos**: no las edites en el proyecto, edítalas aquí.

## Checklist del PR

- [ ] `.\tools\check.ps1` en verde (0 fallos; los avisos, resueltos o justificados).
- [ ] `name` == carpeta y `description` con bloque `NO para ...`.
- [ ] Cuerpo ≤ 400 líneas; el detalle, en `references/`.
- [ ] Español neutro y **tuteo** (sin voseo).
- [ ] Fechas de frescura actualizadas donde corresponda.
- [ ] Evals añadidas o ajustadas en `evals/triggers.json`.
- [ ] `CHANGELOG.md` y `VERSION` según SemVer (ver README → Versionado).

## Convenciones

- **Sin dependencias de runtime**: los scripts son PowerShell sin módulos externos.
- **Encoding**: UTF-8 **sin BOM**, saltos **LF**. Los `.ps1` son **ASCII** (sin acentos, por compatibilidad con Windows PowerShell 5.1). `.gitattributes` fuerza `eol=lf`.
- **Commits**: `tipo(scope): resumen en imperativo` + lista de archivos + verificación.

## Alcance

El Harness es para **openCode** (ver README → Alcance). No lo acoplamos a otros agentes ni añadimos dependencias sin una razón concreta.
