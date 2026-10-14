---
name: harness-freshness
description: Revisar la frescura de las claims del catálogo del Harness (versiones, límites, fechas, enlaces) contrastándolas con las fuentes oficiales y proponer actualizaciones sin aplicarlas. Usar cuando el usuario pida actualizar o verificar el Harness o sus skills. NO para instalar el Harness ('harness-install') ni revisar su calidad editorial.
---

# harness-freshness — Revisor de frescura del catálogo

> El catálogo afirma cosas que envejecen: versiones, límites de free tier, RFC, enlaces. Esta skill **contrasta esas afirmaciones con las fuentes oficiales y propone cambios; no aplica nada sin aprobación**.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Instalar el Harness en un proyecto o actualizarlo | `harness-install` |
| Revisar estilo/calidad editorial de un skill | Editar el propio repositorio (rúbrica rsc) |
| Escribir código de la aplicación del proyecto | La skill del stack (`dotnet`, `sql`, etc.) |

## Qué se considera "fresco"

Toda afirmación del catálogo que pueda **caducar**:

| Tipo de claim | Dónde aparece | Ejemplo |
|---------------|---------------|---------|
| Fecha de frescura | `SKILL.md` (bloque tras el título) | `Frescura (verificado 2026-10-14)` |
| Versiones | `SKILL.md`, `references/` | Angular 21, PostgreSQL 18, .NET 10 LTS |
| Límites/cifras | skills de infra/cloud | 2 OCPU + 12 GB, 750 h de B1s, 1 M de peticiones |
| Enlaces de fuentes | sección **Fuentes** | URLs oficiales |
| Hechos verificados | `Fuentes:` de las skills | RFC, estándares, políticas |

## Procedimiento

1. **Inventario**: listar `SKILL.md` y `references/` de `skills/*`; extraer claims con fecha, versiones, números y URLs. Priorizar por antigüedad de la fecha y por volatilidad (cloud/free tier > versiones > RFC).
2. **Contrastar**: abrir las **fuentes oficiales** indicadas en cada skill (proveedor, estándar, documentación del lenguaje). **No inventar**; si una fuente no se puede verificar, marcarla como `sin confirmar`.
3. **Decidir**: cada claim queda en uno de tres estados:
   - **OK** (vigente; sin cambio),
   - **DESACTUALIZADO** (valor real distinto del publicado),
   - **SIN CONFIRMAR** (la fuente no pudo validarse).
4. **Reportar**: entregar un diff **propuesto** (o una tabla claim → valor actual → valor propuesto → fuente). **No editar archivos** hasta que el usuario diga "aplica" (o equivalente).
5. **Verificar tras aplicar**: volver a ejecutar el paso 1 sobre los archivos tocados para comprobar que las fechas y los valores quedaron coherentes y en español neutro.

## Reglas al proponer

- Cada cambio propone **también** actualizar la **fecha de frescura** de ese archivo al día del hallazgo.
- Cambios de **fondo** (un límite que cambió) requieren mencionar la **fuente y la fecha**; cambios cosméticos no.
- Si un enlace oficial murió: proponer reemplazo o eliminación; nunca dejar enlaces rotos como "verificados".
- **Idioma**: español neutro, tuteo, sin voseo; la regla §2 de `AGENTS.md` aplica también aquí.

## Plantilla de reporte

```markdown
## Revisión de frescura — YYYY-MM-DD

| Archivo | Claim | Estado | Propuesto | Fuente |
|---------|-------|--------|-----------|--------|
| skills/aws/SKILL.md | Free Tier con créditos desde 2025-07-15 | OK | — | aws.amazon.com/free |
| skills/oci/SKILL.md | Always Free 2 OCPU + 12 GB | DESACTUALIZADO | 4 OCPU + 24 GB | docs.oracle.com/... |

### Cambios propuestos (pendientes de aprobación)
- `skills/aws/SKILL.md`: ...
```

## Checklist

- [ ] Inventario de claims con fecha/versión/número/URL hecho
- [ ] Fuentes oficiales abiertas (sin datos de la conversación ni de memoria)
- [ ] Estado asignado a cada claim (OK / DESACTUALIZADO / SIN CONFIRMAR)
- [ ] Fechas de frescura propuestas para los archivos tocados
- [ ] Reporte con diff propuesto; **sin ediciones aplicadas**
- [ ] Español neutro y sin voseo en las propuestas

## Anti-patrones

| Anti-patrón | Problema |
|-------------|----------|
| Aplicar cambios sin aprobación | El catálogo cambia sin revisión |
| "Verificar" de memoria | No es verificación; la regla §3 exige fuente |
| Actualizar solo la fecha sin cambiar el valor | Da falsa confianza |
| Ignorar `references/` | Las cifras suelen vivir ahí, no en el cuerpo |
