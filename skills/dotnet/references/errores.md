# Manejo de errores global — código

Las reglas están en el `SKILL.md`; acá va el código.

## `GlobalExceptionHandler`

Un solo manejador central captura excepciones no controladas, las **loguea** y responde 500 genérico:

```csharp
public class GlobalExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext ctx, Exception ex, CancellationToken ct)
    {
        _logger.LogError(ex, "Error no controlado");
        var response = new ApiResponse<object>
        {
            IsSuccess = false,
            StatusCode = 500,
            Message = "Ha ocurrido un error interno."
        };
        ctx.Response.StatusCode = 500;
        ctx.Response.ContentType = "application/json";
        await ctx.Response.WriteAsJsonAsync(response, ct);
        return true;
    }
}
```

Registro:

```csharp
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
// ...
app.UseExceptionHandler();
```

## Error de modelo (400) uniforme

```csharp
builder.Services.AddControllers()
    .ConfigureApiBehaviorOptions(opts =>
    {
        opts.InvalidModelStateResponseFactory = ctx =>
        {
            var errors = ctx.ModelState.Values
                .SelectMany(v => v.Errors)
                .Select(e => e.ErrorMessage)
                .ToList();
            return new BadRequestObjectResult(new ApiResponse<object>
            {
                IsSuccess = false, StatusCode = 400,
                Message = "Datos de entrada inválidos.", Errors = errors
            });
        };
    });
```
