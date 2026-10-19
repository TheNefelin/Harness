# Configuración y fail-fast

> Detalle de la sección **Configuración y fail-fast** de la skill `dotnet`.

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
