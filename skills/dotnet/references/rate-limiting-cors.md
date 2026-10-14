# Rate limiting y CORS — código

Las reglas están en el `SKILL.md`; acá va el código.

## Rate limiting por cliente

```csharp
builder.Services.AddRateLimiter(opts =>
{
    opts.RejectionStatusCode = 429;
    opts.AddFixedWindowLimiter("fixed", lim =>
    {
        lim.PermitLimit = 10;
        lim.Window = TimeSpan.FromMinutes(1);
        lim.QueueLimit = 0;
        lim.PartitionKey = PartitionKey.Get<HttpContext>(ctx =>
        {
            // detrás de proxy/load balancer
            var fwd = ctx.Request.Headers["X-Forwarded-For"].FirstOrDefault();
            return string.IsNullOrWhiteSpace(fwd)
                ? ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown"
                : fwd;
        });
    });
});
// ...
app.UseRateLimiter();
// en controladores sensibles:
[EnableRateLimiting("fixed")]
```

**Anti-patrón**: rate limit global sin partición por IP → un solo usuario abusivo bloquea a todos, o la regla no aplica tras un proxy porque todos llegan con la IP del balanceador.

## CORS (allow-list explícita)

```csharp
var cors = config.GetSection("Cors").Get<string[]>() ?? Array.Empty<string>();
builder.Services.AddCors(o => o.AddPolicy("Default", p =>
    p.WithOrigins(cors).AllowAnyHeader().AllowAnyMethod()));
```

**Regla**: `WithOrigins` con lista explícita. **Nunca** `SetIsOriginAllowed(_ => true)` ni `AllowAnyOrigin()` en producción, salvo API pública documentada.
