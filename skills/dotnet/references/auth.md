# Autenticación y autorización — código

Las reglas están en el `SKILL.md`; acá va el código.

## Contraseñas (PBKDF2)

Formato **versionado** (`algoritmo:iteraciones:salt:hash`): permite subir el coste más adelante sin invalidar los hashes guardados. 600.000 iteraciones = recomendación OWASP para PBKDF2-HMAC-SHA256.

```csharp
private const int Iterations = 600_000;
private const int SaltSize = 16;
private const int HashSize = 32;
private static readonly HashAlgorithmName Algo = HashAlgorithmName.SHA256;

public static string HashPassword(string password)
{
    byte[] salt = RandomNumberGenerator.GetBytes(SaltSize);
    byte[] hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, Algo, HashSize);
    return $"{Algo.Name.ToLowerInvariant()}:{Iterations}:" +
           $"{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}";
}

// Valida la credencial y señaliza si conviene re-hashear con el coste vigente.
public static bool VerifyPassword(string password, string stored, out bool needsRehash)
{
    needsRehash = false;
    var parts = stored.Split(':');
    if (parts.Length != 4) return false;
    var algo = new HashAlgorithmName(parts[0].ToUpperInvariant());
    int iterations = int.Parse(parts[1]);
    byte[] salt = Convert.FromBase64String(parts[2]);
    byte[] expected = Convert.FromBase64String(parts[3]);
    byte[] actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, algo, expected.Length);
    needsRehash = iterations < Iterations; // upgrade progresivo de hashes antiguos
    return CryptographicOperations.FixedTimeEquals(actual, expected);
}
```

**Nunca**: texto plano, MD5, SHA1, o el mismo hash para todos los usuarios (sin salt). Al iniciar sesión, si `VerifyPassword` marca `needsRehash`, re-hashear con el coste vigente y guardar.

## JWT

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

## ApiKey global (separada del JWT)

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
