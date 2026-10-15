# Dapper — referencia (.NET)

> Acceso a datos con Dapper sobre SQL Server o PostgreSQL. Complementa `dotnet/SKILL.md` §4. El diseño del esquema y de los SPs vive en la skill `sql`.

## Contexto

Dapper es un micro-ORM: extiende `IDbConnection` con métodos `Query*/Execute*`. No hay change tracking ni migraciones; el SQL es tuyo. La conexión se abre y cierra por operación (el *connection pooling* del driver la reutiliza):

```csharp
using var connection = new SqlConnection(_factory.ConnectionString); // o NpgsqlConnection
```

**Regla**: Dapper no valida tu SQL; parametriza siempre (nunca concatenes) y prueba las consultas contra la BD real.

## Consultas

| Método | Uso |
|--------|-----|
| `QueryAsync<T>` | Lista de filas |
| `QueryFirstOrDefaultAsync<T>` | Una fila o `null` (lo más común en `GetById`) |
| `QuerySingleOrDefaultAsync<T>` | Exactamente 0 o 1 fila (falla si hay más de una) |
| `ExecuteScalarAsync<T>` | Un único valor (`COUNT`, `nextval`) |
| `ExecuteAsync` | INSERT/UPDATE/DELETE, devuelve filas afectadas |

```csharp
public async Task<User?> GetByEmailAsync(string email, CancellationToken ct)
{
    using var connection = new SqlConnection(_factory.ConnectionString);
    const string sql = "SELECT id, email, created_at FROM app_users WHERE email = @Email";
    return await connection.QueryFirstOrDefaultAsync<User>(sql, new { Email = email });
}
```

## Parámetros

- **Objeto anónimo** para lo simple: `new { Email = email, Status = "active" }`.
- **`DynamicParameters`** para parámetros de salida, tipos explícitos o nombres dinámicos.
- **Listas / `IN`**: Dapper expande una colección; no armes el `IN` a mano.

```csharp
const string sql = "SELECT id, name FROM app_products WHERE category_id IN @Ids";
var rows = await connection.QueryAsync<Product>(sql, new { Ids = categoryIds });
```

- Usa **`DbType` explícito** cuando el valor puede ser `null` o el motor necesita precisión de tipo.

## Stored procedures con contrato de respuesta

Patrón para que la capa de aplicación no adivine el resultado (el SP se define en la skill `sql`):

```csharp
public async Task<LoginResult> LoginAsync(string email, string passwordHash, CancellationToken ct)
{
    using var connection = new SqlConnection(_factory.ConnectionString);
    var p = new DynamicParameters();
    p.Add("@Email", email);
    p.Add("@PasswordHash", passwordHash);
    p.Add("@IsSuccess", dbType: DbType.Boolean, direction: ParameterDirection.Output);
    p.Add("@StatusCode", dbType: DbType.Int32, direction: ParameterDirection.Output);
    p.Add("@Message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    await connection.ExecuteAsync("Auth_Login", p, commandType: CommandType.StoredProcedure);

    if (!p.Get<bool>("@IsSuccess"))
        return LoginResult.Fail(p.Get<int>("@StatusCode"), p.Get<string>("@Message"));
    return LoginResult.Ok();
}
```

## Multi-mapping (split)

Para traer una relación en una sola consulta:

```csharp
const string sql = """
    SELECT o.id, o.total, c.id, c.name
    FROM app_orders o JOIN app_customers c ON c.id = o.customer_id
    WHERE o.id = @Id
    """;
return await connection.QueryAsync<Order, Customer, Order>(sql,
    (order, customer) => { order.Customer = customer; return order; },
    new { Id = id }, splitOn: "id");
```

## Transacciones

```csharp
using var connection = new SqlConnection(_factory.ConnectionString);
await connection.OpenAsync();
using var tx = connection.BeginTransaction();
try
{
    await connection.ExecuteAsync(sql1, p1, tx);
    await connection.ExecuteAsync(sql2, p2, tx);
    await tx.CommitAsync();
}
catch { await tx.RollbackAsync(); throw; }
```

Transacciones **cortas**. Para lotes grandes usa `SqlBulkCopy` / `COPY` (ver skill `sql`).

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| Concatenar valores en SQL | Inyección | Objeto anónimo / `DynamicParameters` |
| Mapear a `SELECT *` con columnas de más | Valores en `default` silenciosos | Enumerar columnas con alias que coincidan con el DTO |
| Conexión estática/compartida | Concurrencia rota | Crear `IDbConnection` por operación (el pool la reutiliza) |
| Olvidar `commandType: StoredProcedure` | Se interpreta como SQL crudo | Especificarlo |
| Ignorar `CancellationToken` | Requests colgados consumen recursos | Propagar `ct` a los métodos async |
| Un query por fila (N+1) | Muchos round-trips | Carga por lotes / multi-mapping / `IN` |
