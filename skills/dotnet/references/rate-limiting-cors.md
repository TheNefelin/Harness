# Rate limiting y CORS — código

Las reglas están en el `SKILL.md`; acá va el código.

## Rate limiting por cliente

```csharp
builder.Services.AddRateLimiter(opts =>
{
    opts.RejectionStatusCode = 429;
    // Política particionada por cliente: PartitionedRateLimiter + RateLimitPartition.
    opts.AddPolicy("per-client", ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: ClientKey(ctx),
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            }));
});

// Clave de partición por IP. Detrás de proxy NO leer X-Forwarded-For crudo:
// es falsificable. Habilitar ForwardedHeaders con proxies conocidos (abajo).
static string ClientKey(HttpContext ctx) =>
    ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown";

// ...
app.UseRateLimiter();
// en controladores sensibles:
[EnableRateLimiting("per-client")]
```

```csharp
// Program.cs, ANTES de UseRateLimiter: confiar solo en proxies conocidos.
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
    KnownProxies = { IPAddress.Parse("10.0.0.10") }, // IP real del balanceador
});
```

**Anti-patrón**: rate limit global sin partición por cliente → un abusivo bloquea a todos; o particionar por el primer valor de `X-Forwarded-For` → un atacante lo falsifica y evita el límite.

## CORS (allow-list explícita)

```csharp
var cors = config.GetSection("Cors").Get<string[]>() ?? Array.Empty<string>();
builder.Services.AddCors(o => o.AddPolicy("Default", p =>
    p.WithOrigins(cors).AllowAnyHeader().AllowAnyMethod()));
```

**Regla**: `WithOrigins` con lista explícita. **Nunca** `SetIsOriginAllowed(_ => true)` ni `AllowAnyOrigin()` en producción, salvo API pública documentada.
