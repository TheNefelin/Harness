# Swagger / OpenAPI (compatibilidad de versiones)

> Detalle de la sección **Swagger / OpenAPI** de la skill `dotnet`. La versión de Swashbuckle define la API de `Microsoft.OpenApi`.

| Swashbuckle | Microsoft.OpenApi | Nota |
|-------------|-------------------|------|
| 6.x | 1.x | `OpenApiSchema`, `OpenApiReference` (legado, aún válido) |
| 9.x | 1.x | Igual que 6.x pero más actualizada |
| 10.x | **2.x** | **Breaking**: `OpenApiSchema` no existe, `Type` es `JsonSchemaType?`, `OpenApiReference` eliminado |

## Ejemplo de filter compatible (OpenApi 2.x, Swashbuckle 10+)

```csharp
// en OpenApi 2.x el namespace Microsoft.OpenApi.Models fue reemplazado por Microsoft.OpenApi
var schemeRef = new OpenApiSecuritySchemeReference("Bearer");
operation.Security = [new OpenApiSecurityRequirement { { schemeRef, new List<string>() } }];
// para OpenApi 1.x (6.x/9.x) se usaba:
//   new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
```

Endpoint de Swagger en `Program.cs` — usar **ruta absoluta** para evitar problemas tras proxies/host virtuales:

```csharp
app.UseSwagger();
app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "WebApiCore v1"));
```

**Gotchas reales detectados**:
- Si `index.html`/`index.js` de Swagger se sirven con `Cache-Control` largo, el navegador cachea la UI vieja y muestra errores como *"does not specify a valid version field"* aunque el JSON sea válido. Probar con **Ctrl+Shift+R** (hard reload) o incógnito antes de concluir que el spec está roto.
- Validar el spec en `/swagger/v1/swagger.json` directamente, no la página HTML.
- Si Swashbuckle 9.x da problemas de render (UI rota en producción), **bajar a 6.6.2** es una solución validada que conserva todo el spec.
