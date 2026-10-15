---
name: sql
description: Bases de datos relacionales (SQL Server + PostgreSQL/postgres): modelado de esquema, tablas e índices, consultas y su rendimiento. Usar al diseñar o revisar un esquema, ajustar un índice, optimizar una consulta lenta (revisar su plan de ejecución con explain) y planificar transacciones y migraciones. NO para NoSQL/caché ('nosql') ni el acceso desde el ORM/código ('dotnet'/'fastapi').
---

# Bases de datos relacionales — Patrón senior (SQL Server + PostgreSQL)

> Conocimiento transversal de bases de datos relacionales. Lo común va en este archivo; lo específico de cada motor, en `references/sqlserver.md` y `references/postgresql.md`.

**Referencias** (se leen bajo demanda, rutas relativas a esta skill): `references/sqlserver.md`, `references/postgresql.md`. El uso del ORM vive en la skill de cada stack (`dotnet` para Dapper/EF Core, `fastapi` para SQLAlchemy).

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| MongoDB, Cosmos DB, Redis, DynamoDB; caché o documental | `nosql` |
| Cómo consultar la BD desde el ORM (Dapper, EF Core, SQLAlchemy) | `dotnet` / `fastapi` |
| Diseño visual / mockups (si el problema es de UI, no de datos) | `ui-ux-mockup` |

El **diseño del esquema y la consulta SQL** (motor-agnóstico) vive aquí; el **acceso desde el código** es `dotnet`/`fastapi`.

> **Frescura (verificado 2026-10-13):** sintaxis conforme a **SQL:2023 (ISO/IEC 9075:2023)**; PostgreSQL **18** es la versión estable (2025-09-25, soporte 5 años). Las notas de SQL Server son estables entre versiones recientes.

---

## 1. Modelado y esquema

- **Normaliza por defecto (3FN)**: cada hecho en un solo lugar. Desnormaliza solo con una razón medida (rendimiento demostrado con datos, no supuesta).
- **Clave primaria**: surrogate (entero/identity) como PK; expón una **clave natural** como `UNIQUE` cuando exista (email, slug, código). Usa **UUID v7** (ordenable por tiempo) si necesitas IDs distribuidos o no exponer secuencias; evita UUID v4 como PK agrupada (fragmenta los índices).
- **Claves foráneas**: siempre declaradas, con **índice** sobre la FK. Nombra los constraints (`fk_orders_customer`) para que las migraciones y los errores sean legibles.
- **Acciones de borrado explícitas**: `ON DELETE CASCADE` solo cuando la relación sea de composición real (el hijo no existe sin el padre). En general, borrado explícito en la capa de servicio (no cascadas ocultas).
- **Tipos**: dinero en **entero (centavos)** o `DECIMAL`, nunca `float`; fechas en **UTC** (`timestamptz` en Postgres, `datetimeoffset` en SQL Server); strings con longitud acotada; boolean real; enums como **tabla catálogo** con FK, no como strings mágicos.
- **Prefijo de tablas por proyecto** (p. ej. `app_`) cuando la BD es compartida: facilita aislar y dropear solo tus tablas en los tests.
- **Campos de auditoría**: `created_at`/`updated_at` (y `created_by`/`updated_by` si aplica) gestionados por la BD (`server_default`/`onupdate`) o por el ORM de forma consistente.
- **Soft delete** (`deleted_at` que nulo) cuando haga falta conservar historial; si no, borrado físico. No mezclar ambos sin criterio.

## 2. Consultas e índices

- **Parametriza siempre**: nunca concatenes valores en el SQL (inyección + planes incumplidos). Los ORM y Dapper lo hacen; el peligro está en el SQL crudo.
- **Índices guiados por el acceso real**: indexa por las columnas de `WHERE`/`JOIN`/`ORDER BY` frecuentes; el índice de la FK no es opcional. Más índices = escrituras más lentas: no indexar "por si acaso".
- **Índices compuestos**: el orden de columnas importa (el filtro más selectivo y las columnas de igualdad antes que las de rango). Un índice `(a, b)` sirve para `WHERE a = …` y `a = … AND b = …`, no para `WHERE b = …`.
- **Índices cubrientes**: incluir las columnas del `SELECT` evita ir a la tabla (clave para listados).
- **Evita N+1**: carga por lotes (`WHERE id IN (...)`) o `JOIN`, no una consulta por fila. En ORM, revisa las consultas que emite (eager loading / `Include`).
- **Paginación**: **keyset/seek** (`WHERE (sort, id) > (último)`) para listas grandes y scroll; `OFFSET/FETCH`/`LIMIT OFFSET` solo para volúmenes bajos o saltos a página (se degrada al crecer el offset).

## 3. Transacciones y concurrencia

- **Transacciones cortas**: abre, ejecuta lo mínimo, confirma. Una transacción larga bloquea y escala peor que cualquier índice faltante.
- **Nivel de aislamiento explícito** según la necesidad: por defecto `READ COMMITTED`. Si lees y luego escribes sobre lo mismo, cuida las **condiciones de carrera** (row versioning / `SELECT … FOR UPDATE` / lock optimista con `rowversion`/`xmin`).
- **Idempotencia**: para operaciones repetibles (webhooks, reintentos), constraints `UNIQUE` + upsert (`MERGE` en SQL Server, `INSERT … ON CONFLICT` en Postgres) en vez de "leer y decidir" en la aplicación.
- **Reintentos transitorios**: ante deadlocks/errores de conexión, reintentar con backoff (los deadlock son normales bajo concurrencia alta).

## 4. Migraciones y evolución

- **Migraciones versionadas** (EF Core Migrations, Flyway, Liquibase, Alembic, o scripts numerados): nunca cambios manuales a producción. Cada migración debe ser **reversible** o tener un plan de rollback explícito.
- **Cambios compatibles primero**: agregar columnas nulas o con default, desplegar el código que las usa, y recién después quitar las viejas (patrón expandir/contraer) para no romper versión anterior durante el despliegue.
- **Datos vs. esquema**: separa migraciones de esquema y de datos; los seed deben ser **idempotentes** (por clave natural, no por IDs en duro).
- **Réplica de la BD real en tests**: un esquema de prueba distinto al de producción (otro motor, otro tipo de dato) invalida los tests. Usa el mismo motor.

## 5. Diferencias clave entre motores

| Tema | SQL Server | PostgreSQL |
|------|-----------|------------|
| Texto | `NVARCHAR(n)` / `VARCHAR(n)` | `text` o `varchar(n)` (sin `N`) |
| Fecha/hora | `datetime2`, `datetimeoffset` | `timestamptz`, `timestamp` |
| Booleano | `BIT` | `boolean` |
| Auto-ID | `IDENTITY` | `GENERATED … AS IDENTITY` (`serial` legacy) |
| Devolver filas tras escribir | `OUTPUT` | `RETURNING` |
| Upsert | `MERGE` (con cuidado) o `UPDATE`+`INSERT` | `INSERT … ON CONFLICT` |
| UUID | `UNIQUEIDENTIFIER` | `uuid` |
| Paginación | `OFFSET … FETCH NEXT` | `LIMIT … OFFSET` |
| Semántica de identificadores | `[corchetes]` | `"comillas dobles"` (no citar fuerza minúsculas) |
| JSON | funciones JSON / `JSON` (sin índices GIN) | `json` / `jsonb` (indexable con GIN) |
| Diagnóstico | execution plans, `sys.dm_*`, Query Store | `EXPLAIN (ANALYZE, BUFFERS)`, `pg_stat_statements` |

## 6. Anti-patrones

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| Concatenar valores en SQL | Inyección + planes no reutilizables | Parametrizar siempre |
| Dinero en `float` | Errores de redondeo | Entero (centavos) o `DECIMAL` |
| Fecha local sin zona | Ambigüedad y bugs de horario | UTC (`timestamptz`/`datetimeoffset`) |
| FK sin índice | Joins y borrados lentos | Índice sobre cada FK |
| `SELECT *` en código de app | Acopla al esquema; trae de más | Enumerar columnas |
| Paginación con `OFFSET` grande | Degrada al crecer | Keyset/seek |
| N+1 | Cientos de consultas por request | Carga por lotes / JOIN |
| Cambios de esquema a mano | Drift, sin auditoría | Migraciones versionadas |
| Sin constraints (UNIQUE/FK/CHECK) | Integridad solo "en el código" | Declarar en la BD |
| Tests contra otro motor | Verde en falso | Mismo motor que producción |

## 7. Patrones copiables (Bad → Good)

**Parametrización** (nunca concatenar valores):
```sql
-- ❌ Bad: la app concatena el valor → inyección + plan no reutilizable
SELECT id, email FROM app_users WHERE email = 'cualquiera';

-- ✅ Good: parámetro — PostgreSQL ($1) / SQL Server (@Email)
SELECT id, email FROM app_users WHERE email = $1;
SELECT id, email FROM app_users WHERE email = @Email;
```

**Paginación** (keyset para volúmenes grandes):
```sql
-- ❌ Bad: OFFSET grande degrada al crecer
SELECT id, name FROM app_products ORDER BY id LIMIT 20 OFFSET 100000;

-- ✅ Good: keyset/seek (id > último visto)
SELECT id, name FROM app_products WHERE id > 100000 ORDER BY id LIMIT 20;
```

**Upsert idempotente** (webhooks, reintentos):
```sql
-- PostgreSQL
INSERT INTO app_users (email, name) VALUES ('a@x.com', 'A')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- SQL Server
MERGE app_users AS t
USING (SELECT 'a@x.com' AS email, 'A' AS name) AS s ON t.email = s.email
WHEN MATCHED THEN UPDATE SET name = s.name
WHEN NOT MATCHED THEN INSERT (email, name) VALUES (s.email, s.name);
```

**Nota (SQL Server):** Microsoft documenta que `MERGE` tiene comportamiento sorprendente bajo concurrencia; por eso el **patrón principal** es la alternativa transaccional, y `MERGE` queda como opción contextual:

```sql
-- ✅ Preferido en SQL Server: UPDATE + INSERT dentro de una transacción
BEGIN TRAN;
UPDATE app_users SET name = 'A' WHERE email = 'a@x.com';
IF @@ROWCOUNT = 0
    INSERT INTO app_users (email, name) VALUES ('a@x.com', 'A');
COMMIT;
```

**Dinero** (nunca `float`):
```sql
-- ❌ Bad
price float
-- ✅ Good
price_cents integer NOT NULL CHECK (price_cents >= 0)
```

## 8. Checklist

- [ ] Esquema normalizado (o desnormalización justificada y medida)
- [ ] PK definida; clave natural como `UNIQUE`
- [ ] FKs declaradas **con índice**
- [ ] Tipos correctos (dinero entero/DECIMAL, fechas UTC, longitudes)
- [ ] Enums como tabla catálogo, no strings mágicos
- [ ] Consultas parametrizadas
- [ ] Índices guiados por el acceso real (no de más)
- [ ] Paginación por keyset en listados grandes
- [ ] Transacciones cortas y con isolation explícito
- [ ] Migraciones versionadas, reversibles e idempotentes
- [ ] Tests contra el mismo motor que producción

## 9. Fuentes

- **Sintaxis / estándar**: ISO/IEC *9075:2023* (SQL:2023).
- **Keyset pagination y `ON CONFLICT`**: PostgreSQL docs (`postgresql.org/docs`).
- **`MERGE` y aislamiento**: SQL Server docs / Microsoft Learn (`learn.microsoft.com`).
