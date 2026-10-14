---
name: dotnet
description: Patrón senior para APIs REST en .NET (ASP.NET Core) con Clean Architecture, Dapper o Entity Framework Core sobre SQL Server o PostgreSQL, incluidos clientes MAUI (MVVM). Usar cuando se cree, modifique o revise código .NET/C#: controladores, servicios, repositorios, capa de datos, auth, manejo de errores o testing. NO usar para APIs Python/FastAPI (eso es la skill 'fastapi'), diseño de esquema, índices o motores de BD (eso es 'sql' o 'nosql'), ni frontend Angular/Astro (eso es 'angular' o 'astro').
---

# SKILL: .NET (C#) — Patrón Senior (transversal)

Guía de referencia para construir APIs REST en **.NET (ASP.NET Core)** siguiendo una arquitectura y convenciones senior validadas en producción (`WebApiCore`, Clean Architecture). La **capa de datos** usa **Dapper o Entity Framework Core** sobre **SQL Server o PostgreSQL**; la elección se documenta en §4. El diseño de esquema, tipos y motores vive en la skill **`sql`**; el modelado documental/caché, en la skill **`nosql`**. Es **transversal**: los ejemplos son genéricos (auth, CRUD, manejo de errores, configuración) y aplican a cualquier dominio. Cubre también buenas prácticas para clientes **MAUI** (MVVM) porque comparten las mismas reglas de C#, seguridad y testing.

Este archivo es un **skill**: se lee para replicar el patrón en cualquier proyecto .NET nuevo. No es una receta dogmática; es la lista de decisiones que convierten un CRUD simple en un backend mantenible, seguro y desplegable.

**Referencias** (se leen bajo demanda, ruta relativa a esta skill): `references/maui.md` (clientes MAUI), `references/dapper.md` (acceso a datos con Dapper), `references/efcore.md` (acceso a datos con EF Core).

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| API en Python / FastAPI / SQLAlchemy | `fastapi` |
| Diseño de esquema, tipos, índices, constraints o migraciones del motor | `sql` (SQL Server / PostgreSQL) o `nosql` |
| Frontend Angular o Astro | `angular` / `astro` |
| Diseño visual / mockups previos a implementar | `ui-ux-mockup` |

El **cómo** se escribe C#/.NET (Clean Architecture, envelope, auth, capa de datos) vive aquí; el **esquema de la BD** es `sql`, y el **frontend** es `angular`/`astro`.

---

## 1. ¿Por qué este patrón es SENIOR?

Porque resuelve los problemas que matan a las APIs .NET cuando crecen, con decisiones **justificadas**, no por moda:

| Decisión | Problema que resuelve |
|----------|----------------------|
| **Clean Architecture por capas** (`Domain` → `Application` → `Infrastructure` → `API`) | Dependencias en una sola dirección; la API no conoce repositorios, los servicios no conocen Dapper. Cambiar de ORM o de BD no toca la capa de aplicación |
| **Envelope uniforme `ApiResponse<T>`** | Toda respuesta (éxito y error) tiene el mismo contrato `{isSuccess, statusCode, message, data, errors}`. El frontend tiene un solo patrón de consumo |
| **`GlobalExceptionHandler` → 500 genérico + `ProblemDetails`** | El detalle real de la excepción va al log, nunca al cliente. Sin fuga de stack traces ni internos |
| **Fail-fast de configuración** | Config inválida (connection string faltante, CORS vacío, JWT sin sección) → excepción al arrancar, no fallas en runtime difíciles de diagnosticar |
| **Connection string por entorno** (`Development` → local, resto → producción) | El mismo código corre en local y en producción sin tocar el repositorio; la config correcta la decide el entorno |
| **JWT identifica + `ApiKey` global** | Separa "quién puede llamar a la API" (ApiKey del origen, validada contra BD) de "quién es el usuario" (JWT) |
| **Rate limiting por cliente (`X-Forwarded-For` → IP)** | Protección de fuerza bruta que no bloquea a todos los usuarios por igual |
| **Contraseñas con PBKDF2 (KDF)** | Hash seguro con salt e iteraciones configurables; nunca almacenar texto plano ni MD5/SHA simples |
| **Dapper o EF Core, sobre SQL Server o PostgreSQL** | Acceso a datos explícito y sin dependencia del ORM en el dominio; la capa Application no conoce el ORM ni el motor |
| **Tests de integración con BD real** | Validan el flujo completo (DTO → SP → respuesta) contra la base real, no contra mocks que mienten |
| **Sin secretos en el código** | Connection strings, claves JWT y ApiKeys van en configuración/secrets del entorno, nunca hardcodeadas ni en el repo |

---

## 2. Stack recomendado

| Capa | Tecnología | Nota |
|------|-----------|------|
| API | ASP.NET Core (net8/net9/net10 según contexto) | Web API con Controllers, no minimal API para CRUD corporativo |
| ORM | **Dapper** o **Entity Framework Core** | Elegir por caso (§4); ver `references/dapper.md` / `references/efcore.md` |
| BD | **SQL Server** o **PostgreSQL** | Esquema y motores según la skill `sql` |
| Auth | JWT (Microsoft.AspNetCore.Authentication.JwtBearer) + ApiKey propio | Filter/attr |
| Rate limiting | ASP.NET Core RateLimiter | Fixed window + partition por IP |
| Logs | ILogger + GlobalExceptionHandler | Sin librería de terceros necesaria |
| Tests | xUnit + WebApplicationFactory | Integración contra BD real |
| Serialización | System.Text.Json | CamelCase, sin ciclos |
| Documentación | Swagger/Swashbuckle | Versionado compatible (ver §10) |

> **Frescura (verificado 2026-10-13):** .NET 10 es **LTS** desde el **2025-11-11** (soporte hasta 2028-11-10) e incluye **C# 14** y **EF Core 10**; .NET 8 y .NET 9 llegan a **fin de soporte el 2026-11-10**. Fuente: .NET Blog, *Announcing .NET 10* (2025-11-11); Microsoft Learn, *What's New in EF Core 10*.

---

## 3. Estructura de carpetas (Clean Architecture)

```
WebApiCore.sln
├── WebApiCore.Domain/          # Modelos, DTOs, entidades (sin dependencias)
│   └── Models/                 # e.g. ApiResponse<T>, User, LoginRequest
├── WebApiCore.Application/     # Servicios y lógica de negocio
│   └── Services/               # e.g. UserService, AuthService
├── WebApiCore.Infrastructure/  # Acceso a datos (Dapper, context, SPs)
│   ├── Repositories/
│   ├── Context/                # IDapperContext
│   └── Mappings/
└── WebApiCore/                 # API (Program.cs, Controllers, Filters)
    ├── Controllers/
    ├── Filters/                # ApiKeyOperationFilter, AuthorizeOperationFilter, GlobalExceptionHandler
    ├── Middleware/
    ├── Models/
    └── appsettings.json        # + appsettings.{Environment}.json
```

Reglas de dependencia (una sola dirección):
- `Domain` no conoce a nadie.
- `Application` conoce a `Domain`.
- `Infrastructure` conoce a `Application` (y `Domain`).
- `WebApiCore` (API) conoce a todos, pero **nadie la conoce a ella**.

**Anti-patrón clásico**: un solo proyecto `WebApiCore` con `Models/Repositories/Services/Controllers` todos juntos. Funciona el primer año; luego las dependencias se mezclan y migrar de ORM o de BD rompe todo.

---

## 4. Capa de datos (Dapper o EF Core, sobre SQL Server o PostgreSQL)

La elección del ORM es una **decisión explícita**, no una imposición. Ambos respetan Clean Architecture: los repositorios viven en `Infrastructure`, exponen interfaces y la capa `Application` no los conoce.

| ORM | Cuándo elegirlo | Detalle |
|-----|-----------------|---------|
| **Dapper** | Control total del SQL, stored procedures, consultas a medida, máximo rendimiento. Cuando la lógica de datos vive (también) en la BD | `references/dapper.md` |
| **EF Core** | Modelo de dominio rico, migraciones, LINQ, change tracking, evolución del esquema | `references/efcore.md` |

- El diseño del esquema, tipos, índices y motores (SQL Server / PostgreSQL) está en la skill **`sql`**.
- La lógica de negocio **nunca** vive en la capa de datos: los repositorios reciben datos ya procesados (p. ej. el `passwordHash` ya calculado).

### Connection string por entorno (fail-fast)

```csharp
public interface IDbConnectionFactory
{
    string ConnectionString { get; }
}

public class DbConnectionFactory : IDbConnectionFactory
{
    public string ConnectionString { get; }

    public DbConnectionFactory(IConfiguration config, IHostEnvironment env)
    {
        // La clave depende del motor ("SqlServer" | "Postgres"); debe existir.
        var name = config["Database:ConnectionName"] ?? "Default";
        var conn = env.IsDevelopment()
            ? config.GetConnectionString(name)
            : config.GetConnectionString($"{name}Web");

        // Fail-fast: si falta, la API no arranca.
        if (string.IsNullOrWhiteSpace(conn))
            throw new InvalidOperationException($"No se encontró ConnectionStrings:{name}/{name}Web");
        ConnectionString = conn;
    }
}
```

### Ejemplo mínimo con Dapper (detalle en `references/dapper.md`)

```csharp
public async Task<User?> GetByEmailAsync(string email)
{
    using var connection = new SqlConnection(_context.ConnectionString); // o NpgsqlConnection (PostgreSQL)
    const string sql = "SELECT id, email, password_hash FROM app_users WHERE email = @Email";
    return await connection.QueryFirstOrDefaultAsync<User>(sql, new { Email = email });
}
```

Con EF Core, el equivalente es un `DbContext` con `DbSet<User>` y una consulta LINQ (`references/efcore.md`). En ambos casos: **consultas parametrizadas**, sin concatenar valores (ver skill `sql`).


---

## 5. Contrato uniforme de respuesta (Envelope)

Toda respuesta HTTP pasa por el mismo envelope. Esto estabiliza el contrato con el frontend:

```csharp
public class ApiResponse<T>
{
    public bool IsSuccess { get; set; }
    public int StatusCode { get; set; }
    public string Message { get; set; } = string.Empty;
    public T? Data { get; set; }
    public List<string>? Errors { get; set; }
}
```

Controladores lo usan siempre, sin excepciones:

```csharp
[HttpGet("{id}")]
public async Task<IActionResult> GetById(int id)
{
    var user = await _userService.GetByIdAsync(id);
    if (user is null)
        return NotFound(new ApiResponse<object> { IsSuccess = false, StatusCode = 404, Message = "No encontrado" });

    return Ok(new ApiResponse<UserDto> { IsSuccess = true, StatusCode = 200, Message = "OK", Data = user });
}
```

### Tabla de códigos coherente

| Caso | HTTP | Envelope |
|------|------|----------|
| Éxito | 200/201 | `IsSuccess=true` |
| Entrada inválida (modelo/validación) | 400 | `IsSuccess=false`, `Errors` |
| No autenticado | 401 | `IsSuccess=false` |
| Sin permiso | 403 | `IsSuccess=false` |
| No existe | 404 | `IsSuccess=false` |
| Límite de peticiones excedido | 429 | `IsSuccess=false` |
| Error interno | 500 | `IsSuccess=false`, mensaje genérico |

**Anti-patrón**: devolver en unos endpoints `{data: ...}` directo y en otros un `string` de error o `ProblemDetails` crudo. El frontend termina con `if (status === 400) ... else if (typeof res === 'string') ...`.

---

## 6. Manejo de errores global

### `GlobalExceptionHandler`

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

### Error de modelo (400) uniforme

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

**Regla**: el mensaje de 500 es genérico para el cliente; el detalle real va al log. Nunca `ex.Message` en una respuesta 500.

---

## 7. Autenticación y autorización

### Contraseñas (PBKDF2)

```csharp
public static string HashPassword(string password)
{
    byte[] salt = RandomNumberGenerator.GetBytes(16);
    byte[] hash = Rfc2898DeriveBytes.Pbkdf2(
        password, salt, 10000, HashAlgorithmName.SHA256, 32);
    return Convert.ToBase64String(salt) + ":" + Convert.ToBase64String(hash);
}
```

**Nunca**: texto plano, MD5, SHA1, o el mismo hash para todos los usuarios (sin salt).

### JWT

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts =>
    {
        opts.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true, ValidateAudience = true,
            ValidateLifetime = true, ClockSkew = TimeSpan.Zero,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(config["JWT:Key"]!)),
            ValidIssuer = config["JWT:Issuer"],
            ValidAudience = config["JWT:Audience"]
        };
        // 401 uniforme si falla el token
        opts.Events = new JwtBearerEvents
        {
            OnChallenge = ctx =>
            {
                ctx.HandleResponse();
                ctx.Response.StatusCode = 401;
                ctx.Response.ContentType = "application/json";
                return ctx.Response.WriteAsJsonAsync(new ApiResponse<object>
                { IsSuccess = false, StatusCode = 401, Message = "No autorizado." });
            }
        };
    });
```

### ApiKey global (separada del JWT)

El origen (Swagger, Postman, frontend) envía la ApiKey configurada en BD (`Mae_Config`). Se valida en un filtro de acción:

```csharp
public class ApiKeyFilter : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext ctx, ActionExecutionDelegate next)
    {
        if (!ctx.HttpContext.Request.Headers.TryGetValue("X-Api-Key", out var apiKey))
        {
            ctx.Result = new UnauthorizedObjectResult(new ApiResponse<object>
                { IsSuccess = false, StatusCode = 401, Message = "ApiKey requerida." });
            return;
        }
        // comparar contra el valor almacenado en BD (Mae_Config) de forma segura
        var stored = await _configService.GetAsync("ApiKey");
        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(apiKey!),
                Encoding.UTF8.GetBytes(stored)))
        {
            ctx.Result = new UnauthorizedObjectResult(/* 401 uniforme */);
            return;
        }
        await next();
    }
}
```

**Regla**: la ApiKey viaja en header, **nunca en la query string** (queda en logs del servidor y del proxy).

---

## 8. Rate limiting y CORS

### Rate limiting por cliente

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

### CORS (allow-list explícita)

```csharp
var cors = config.GetSection("Cors").Get<string[]>() ?? Array.Empty<string>();
builder.Services.AddCors(o => o.AddPolicy("Default", p =>
    p.WithOrigins(cors).AllowAnyHeader().AllowAnyMethod()));
```

**Regla**: `WithOrigins` con lista explícita. **Nunca** `SetIsOriginAllowed(_ => true)` ni `AllowAnyOrigin()` en producción, salvo API pública documentada.

---

## 9. Configuración y fail-fast

`appsettings.json` (producción) y `appsettings.Development.json` (local) por separado:

```json
{
  "Database": { "ConnectionName": "SqlServer" },
  "ConnectionStrings": {
    "SqlServer": "Server=LOCAL;Database=...;Integrated Security=True",
    "SqlServerWeb": "Server=...;Database=...;User Id=...;Password=...;TrustServerCertificate=True"
  },
  "JWT": { "Key": "...", "Issuer": "...", "Audience": "...", "ExpireMinutes": 60 },
  "Cors": [ "https://origen-frontend" ],
  "RateLimit": { "PermitLimit": 10, "WindowMinutes": 1 }
}
```

Con PostgreSQL, `ConnectionName` = `"Postgres"` y las claves `Postgres`/`PostgresWeb` (p. ej. `Host=localhost;Database=app;Username=...;Password=...`).

Fail-fast: validar la config requerida **al arrancar**, no al primer request:

```csharp
if (string.IsNullOrWhiteSpace(config["JWT:Key"])) throw new InvalidOperationException("JWT:Key no configurada");
```

**Regla de oro**: un servidor que arranca con config inválida es un bug silencioso; uno que lanza excepción es un bug evidente.

**Nunca** commitear `appsettings.json` con secretos reales. Usar `.env`/secrets del proveedor o variables de entorno y mantener en el repo una plantilla `appsettings.Example.json`.

---

## 10. Swagger / OpenAPI (compatibilidad de versiones)

La versión de Swashbuckle define la API de `Microsoft.OpenApi`:

| Swashbuckle | Microsoft.OpenApi | Nota |
|-------------|-------------------|------|
| 6.x | 1.x | `OpenApiSchema`, `OpenApiReference` (legado, aún válido) |
| 9.x | 1.x | Igual que 6.x pero más actualizada |
| 10.x | **2.x** | **Breaking**: `OpenApiSchema` no existe, `Type` es `JsonSchemaType?`, `OpenApiReference` eliminado |

### Ejemplo de filter compatible (OpenApi 2.x, Swashbuckle 10+)

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

---

## 11. MAUI (clientes .NET multiplataforma)

El detalle de MAUI (MVVM, DI, Shell y navegación, Core vs MAUI, timers, audio, Android, firma y publicación en Play) vive en **`references/maui.md`** de esta skill y se lee solo cuando el trabajo involucra una app MAUI.

- Aplican las mismas reglas de C# y seguridad que en la API.
- Antes de tocar una app MAUI, lee `references/maui.md` (ruta relativa a la carpeta de esta skill) y sigue su checklist.

## 12. Tests

- **xUnit + `WebApplicationFactory<T>`** para tests de integración de la API.
- Probar **contra BD real** (o instancia de prueba) para validar DTO → capa de datos → respuesta completa.
- Verificar el **envelope**: `IsSuccess`, `StatusCode`, `Message` correctos para éxito, 400, 401, 404, 429 y 500.
- No mockear repositorios para probar la API: el valor está en el flujo real.
- Comando: `dotnet run --project NavajaSuiza.Test/NavajaSuiza.Test.csproj` (no ejecutar sin autorización del usuario según las reglas del repo). La suite usa xUnit.net v3 con runner in-process; `dotnet test` no es compatible con el SDK de .NET 10.

---

## 13. Checklist final

- [ ] Estructura Clean Architecture con dependencias en una sola dirección.
- [ ] Envelope `ApiResponse<T>` en **todas** las respuestas (éxito y error).
- [ ] `GlobalExceptionHandler` central: log + 500 genérico, sin fuga de internos.
- [ ] 400 uniforme vía `InvalidModelStateResponseFactory`.
- [ ] Contraseñas con PBKDF2 + salt + iteraciones configurables.
- [ ] JWT con `ClockSkew=0`, issuer/audience validados, key desde config.
- [ ] ApiKey en header (nunca en query string) validada contra BD.
- [ ] Rate limiting particionado por IP con `X-Forwarded-For`.
- [ ] CORS con allow-list explícita; sin `AllowAnyOrigin` en producción.
- [ ] Fail-fast de configuración al arrancar.
- [ ] No secretos hardcodeados ni en el repo.
- [ ] Swagger con ruta absoluta y versión de Swashbuckle compatible con OpenApi (6.x/9.x vs 10.x).
- [ ] `dotnet build` sin errores ni warnings.
- [ ] Tests de integración cubriendo los códigos del envelope.
- [ ] Verificación real en runtime (navegador/Swagger) tras el deploy; no basta que compile.
- [ ] Documentar decisiones relevantes en `DEVELOPMENT.md` del proyecto.

---

## 14. Anti-patrones generales (resumen rápido)

| Anti-patrón | Solución |
|-------------|----------|
| Todo en un solo proyecto API | Clean Architecture por capas |
| Respuestas HTTP inconsistentes | Envelope único `ApiResponse<T>` |
| `ex.Message` al cliente en 500 | Log + mensaje genérico |
| Config inválida detectada en runtime | Fail-fast al arrancar |
| Secretos en el código/repo | Config/secrets del entorno |
| `AllowAnyOrigin` / `SetIsOriginAllowed(_=>true)` | Allow-list explícita |
| Hash sin salt o MD5/SHA para contraseñas | PBKDF2 con salt (KDF) |
| Fire-and-forget / `async void` | `async Task` + manejo central |
| `async void OnNavigatedTo` con await de sensores | Síncrono + fire-and-forget con try/catch |
| `catch {}` vacío | Log + estado visible en UI |
| `HttpClient` nuevo por llamada | Singleton inyectado |
| SSL bypass en el cliente | Trust del SO; nunca `_ => true` |
| Migrar de versión sin revisar breaking changes | Verificar matriz de versiones (p.ej. OpenApi 2.x) antes del upgrade |

---

## 15. Referencias del patrón validado

- **Repo de referencia**: `WebApiCore` (Clean Architecture + Dapper + JWT + ApiKey + rate limit + envelope) — deployado y operativo.
- **Migration .NET 10**: `PasswordManager_.NET10` — port del mismo patrón con OpenApi 2.x (Swashbuckle 10.x).
- **Config de despliegue**: connection string de producción por entorno, fail-fast, CORS por allow-list.
- **Documentación**: ver `DEVELOPMENT.md` del proyecto para decisiones de diseño y alternativas descartadas.
