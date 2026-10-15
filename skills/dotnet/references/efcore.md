# Entity Framework Core — referencia (.NET)

> Acceso a datos con EF Core sobre SQL Server o PostgreSQL. Complementa `dotnet/SKILL.md` §4. El diseño del esquema y de los motores vive en la skill `sql`.

## DbContext y provider

```csharp
public class AppDbContext : DbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
        => modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
}

// Program.cs — el provider depende del motor:
builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("SqlServer")));   // SQL Server
    // o.UseNpgsql(builder.Configuration.GetConnectionString("Postgres")));    // PostgreSQL
```

- **Lifetime `Scoped`** por request (default de `AddDbContext`). Para alta concurrencia, `AddDbContextPool` reutiliza instancias.
- No compartas un `DbContext` entre hilos ni lo guardes como singleton.

## Configuración del modelo

Separar por entidad con `IEntityTypeConfiguration<T>` (no todo en `OnModelCreating`):

```csharp
public class UserConfig : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> b)
    {
        b.ToTable("app_users");
        b.HasKey(x => x.Id);
        b.Property(x => x.Email).HasMaxLength(255).IsRequired();
        b.HasIndex(x => x.Email).IsUnique();
        b.Property(x => x.RowVersion).IsRowVersion();  // SQL Server
    }
}
```

- **Conversiones**: `HasConversion` (enum ↔ string con `HasConversion<string>()`); `OwnsOne` para objetos de valor; `jsonb`/JSON con `ToJson()` (PostgreSQL/SqlServer 2025+).
- Nombres de tabla/columnas en la BD según convención de la skill `sql` (snake_case en PostgreSQL).

## Migraciones

```bash
dotnet ef migrations add InitialCreate
dotnet ef database update
```

- Versionadas en el repo; revisa el SQL generado (`dotnet ef migrations script`) antes de aplicar en producción.
- Evita cambios manuales a la BD: el modelo y la BD se mantienen sincronizados por migraciones.
- Patrón **expandir/contraer** para cambios incompatibles (ver skill `sql` §4).

## Consultas

- **`AsNoTracking()`** en lecturas (sin cambio de estado): más rápido y menos memoria.
- **Proyecciones** con `Select` al DTO: trae solo lo que necesitas.

```csharp
var list = await db.Products.AsNoTracking()
    .Where(p => p.CategoryId == categoryId)
    .OrderByDescending(p => p.CreatedAt)
    .Select(p => new ProductDto(p.Id, p.Name, p.Price))
    .Skip(0).Take(20)     // paginación simple; para listas grandes, keyset (skill sql)
    .ToListAsync(ct);
```

- **Relaciones**: `Include`/`ThenInclude` para cargar, o proyección explícita. Para colecciones grandes, `AsSplitQuery()` y evitar la "explosión cartesiana".
- Traduce a SQL lo que puedas en LINQ; revisa el SQL generado (logging) si algo parece lento.

## Concurrencia optimista

Un token de versión en el filtro del `UPDATE` (EF lanza `DbUpdateConcurrencyException` si cambió):

- **SQL Server**: columna `rowversion` con `.IsRowVersion()`.
- **PostgreSQL**: columna `xmin` con `.IsRowVersion()` o un `uint` versionado con `.IsConcurrencyToken()`.

En la capa de servicio, captura `DbUpdateConcurrencyException` y devuelve conflicto (409).

## SQL crudo y stored procedures

```csharp
// Consulta cruda (parametrizada) sobre el modelo
var users = await db.Users
    .FromSqlRaw("SELECT * FROM app_users WHERE email = {0}", email)
    .AsNoTracking().ToListAsync();
```

- `FromSqlRaw`/`FromSqlInterpolated` para consultas; `ExecuteSqlRaw` para escrituras.
- **SPs**: `FromSqlRaw("EXEC Auth_Login @p0", email)` mapeado a la entidad. Para SPs con contrato de salida, Dapper suele ser más directo (ver `references/dapper.md` y skill `sql`).

## Transacciones

```csharp
using var tx = await db.Database.BeginTransactionAsync(ct);
try { await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); }
catch { await tx.RollbackAsync(ct); throw; }
```

Transacciones **cortas**. Un solo `SaveChangesAsync` ya es atómico; usa transacción explícita solo al agrupar varias operaciones.

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| Tracking en lecturas masivas | Memoria y tiempo de más | `AsNoTracking()` |
| `Include` sin proyección | Trae entidades completas y colecciones enormes | `Select` al DTO |
| N+1 silencioso | Una query por fila en bucles | Proyección/`Include` y revisar el SQL generado |
| Contexto `Singleton`/compartido | Estados cruzados, concurrencia rota | `Scoped` por request |
| Migración sin revisar el SQL | Cambios destructivos en producción | `migrations script` + patrón expandir/contraer |
| `FromSqlRaw` concatenando | Inyección | Interpolado/parametrizado |
| Ignorar `DbUpdateConcurrencyException` | Lost updates | Manejar el conflicto (409) |
| Sin `CancellationToken` | Requests colgados | Propagar `ct` |
