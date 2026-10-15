# SQL Server — referencia

> Específico de SQL Server (T-SQL). Complementa `sql/SKILL.md`.

## Tipos

- **Texto de usuario**: `NVARCHAR(n)` (Unicode). Usa `VARCHAR(n)` solo con justificación (ASCII y volumen). `NVARCHAR(MAX)` para texto largo.
- **Fecha/hora**: `datetime2` (precisión y rango) o `datetimeoffset` si guardas la zona. Evita `datetime` (precisión ~3 ms, redondeos) y `smalldatetime`.
- **Booleano**: `BIT`.
- **Dinero**: `DECIMAL(p,s)` (p. ej. `DECIMAL(18,2)`) o entero en centavos. Nunca `float`/`real`.
- **UUID**: `UNIQUEIDENTIFIER`. Para PK clustered usa `NEWSEQUENTIALID()` (evita fragmentación) o un entero; el GUID aleatorio como clustered fragmenta.

## Identidad y claves

- `IDENTITY(1,1)` para surrogate; `SEQUENCE` si necesitas el valor antes del insert o compartido entre tablas.
- PK clustered por defecto sobre el surrogate; claves naturales como `UNIQUE` nonclustered.

## Índices

- **Clustered**: define el orden físico de la tabla; uno por tabla. El `INCLUDE` permite un índice cubriente sin tocar la tabla base.
- **Filtered indexes** (`WHERE deleted_at IS NULL`) para subconjuntos muy consultados (p. ej. filas activas).
- Revisa índices faltantes y no usados con las DMV (`sys.dm_db_index_usage_stats`), no por intuición.

## Transacciones y concurrencia

- Nivel por defecto `READ COMMITTED`; los lectores bloquean escritores. En apps web activa **RCSI** (`ALTER DATABASE … SET READ_COMMITTED_SNAPSHOT ON`) para lectura no bloqueante por versionado.
- **Evita `WITH (NOLOCK)`**: permite lecturas sucias e inconsistentes. RCSI da el mismo beneficio sin el riesgo.
- Transacciones cortas; el lock optimista se hace con una columna `rowversion`.

## Escritura y upsert

```sql
-- Upsert con MERGE (usar HOLDLOCK para evitar carrera en concurrencia alta)
MERGE dbo.app_products AS target
USING (SELECT @Slug AS slug, @Name AS name) AS src
  ON target.slug = src.slug
WHEN MATCHED THEN UPDATE SET name = src.name
WHEN NOT MATCHED THEN INSERT (slug, name) VALUES (src.slug, src.name)
OUTPUT $action, inserted.id;
```

`MERGE` tiene aristas de concurrencia conocidas; en escenarios delicados, prefiere `UPDATE` + `INSERT … WHERE NOT EXISTS` dentro de una transacción. Usa `OUTPUT` para recuperar valores generados en el mismo statement.

## Paginación

`OFFSET … FETCH` **exige un `ORDER BY`** y se degrada con offsets grandes; para listados grandes, keyset:

```sql
SELECT id, created_at, name FROM dbo.app_products
WHERE (created_at, id) < (@lastCreatedAt, @lastId)
ORDER BY created_at DESC, id DESC
OFFSET 0 ROWS FETCH NEXT @take ROWS ONLY;
```

## Stored procedures con contrato de respuesta

Patrón para que la capa de aplicación no adivine el resultado (lo consume la skill `dotnet`):

```sql
CREATE PROCEDURE Auth_Login
    @Email NVARCHAR(100), @PasswordHash NVARCHAR(500),
    @IsSuccess BIT OUTPUT, @StatusCode INT OUTPUT, @Message NVARCHAR(500) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Auth_Users WHERE Email = @Email)
    BEGIN
        SET @IsSuccess = 0; SET @StatusCode = 400; SET @Message = N'Credenciales inválidas'; RETURN;
    END
    -- validar hash…
END
```

## Diagnóstico y rendimiento

- `SET STATISTICS IO, TIME ON` para ver lecturas y tiempos por statement.
- **Execution plans** (en SSMS/Azure Data Studio): busca scans donde esperas seeks, key lookups y sorts costosos.
- **Query Store** para capturar regresiones por plan y *parameter sniffing*.
- Revisa **conversiones implícitas** en el plan: comparar `NVARCHAR` con `VARCHAR` fuerza un scan.

## Conexión y pooling

- Driver recomendado: **`Microsoft.Data.SqlClient`** (no `System.Data.SqlClient`, en desuso).
- El *connection pooling* está activo por defecto; ajusta `Max Pool Size` solo si hay contención medida.
- TLS: no desactives la validación del certificado en producción. `Encrypt=True` con `TrustServerCertificate=True` solo en desarrollo local.

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| `VARCHAR` sin `N` para Unicode | Guarda `?`/pierde caracteres | `NVARCHAR` |
| `datetime` | Redondeos de ~3 ms | `datetime2` |
| GUID aleatorio como PK clustered | Fragmentación, inserts lentos | `NEWSEQUENTIALID()` o entero |
| `NOLOCK` | Lecturas sucias | RCSI |
| Tipos mal emparejados en `JOIN`/`WHERE` | Conversión implícita → scan | Mismos tipos y longitud |
| `MERGE` sin `HOLDLOCK` | Condiciones de carrera | `HOLDLOCK` o patrón `UPDATE`+`INSERT` |
| `OFFSET` sin `ORDER BY` | Error / resultados no deterministas | Siempre `ORDER BY` |
