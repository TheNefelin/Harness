# PostgreSQL — referencia

> Específico de PostgreSQL. Complementa `sql/SKILL.md`.

## Tipos

- **Texto**: `text` (sin límite) o `varchar(n)`. Rendimiento idéntico; usa `varchar(n)` solo como validación de longitud. No hay `NVARCHAR` (todo es Unicode).
- **Fecha/hora**: `timestamptz` (instante, recomendado) o `timestamp` (sin zona). Guarda siempre en UTC.
- **Booleano**: `boolean` (`true`/`false`), sin `BIT`.
- **Dinero**: `numeric(p,s)` (p. ej. `numeric(18,2)`) o entero en centavos. Nunca `real`/`double precision` para dinero.
- **UUID**: `uuid` nativo; `gen_random_uuid()` para generarlo (integrado; `gen_random_uuid` viene con PG 13+).
- **JSON**: `jsonb` (binario, indexable con GIN) preferido sobre `json` (texto, preserva formato). Para datos estructurados con consultas, `jsonb`.
- **Arrays** nativos (`int[]`, `text[]`) y **enums** (`CREATE TYPE … AS ENUM`); el enum nativo es rígido para evolucionar, prefiere tabla catálogo para valores que cambian.
- Evita `char(n)` (padding con espacios sorpresivo).

## Identidad y claves

```sql
CREATE TABLE app_products (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug        text NOT NULL UNIQUE,
    created_at  timestamptz NOT NULL DEFAULT now()
);
```

`GENERATED ALWAYS AS IDENTITY` es el estándar moderno (`serial` es legacy). **No insertes valores explícitos** en columnas `GENERATED ALWAYS` (lanza error); para seeds idempotentes usa `OVERRIDING SYSTEM VALUE` o `ON CONFLICT`.

## Índices

- **B-tree** por defecto (igualdad y rango).
- **GIN** para `jsonb`, arrays y búsqueda de texto (`tsvector`); **GiST** para rangos/similares.
- **Parciales** (`WHERE deleted_at IS NULL`) y **cubrientes** con `INCLUDE` (PG 11+).
- En producción, crea índices con **`CREATE INDEX CONCURRENTLY`** para no bloquear escrituras (no puede correr dentro de una transacción).

## Escritura, upsert y carga masiva

```sql
-- Upsert idempotente (requiere una restricción UNIQUE sobre (slug))
INSERT INTO app_products (slug, name) VALUES (@slug, @name)
ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
RETURNING id, created_at;
```

- `RETURNING` devuelve filas afectadas en el mismo statement.
- Carga masiva: `COPY` (o `\copy`) en vez de miles de `INSERT`.

## Transacciones y concurrencia

- **MVCC**: los lectores no bloquean a los escritores. Nivel por defecto **`READ COMMITTED`**.
- `REPEATABLE READ` = snapshot de la transacción; `SERIALIZABLE` usa **SSI** y puede requerir **reintentos** ante errores de serialización.
- Las transacciones **largas bloquean el `VACUUM`** y generan bloat: mantenelas cortas.

## Diagnóstico y mantenimiento

- **`EXPLAIN (ANALYZE, BUFFERS)`** para ver el plan real, tiempos y uso de buffers (no ejecutes `ANALYZE` sobre escrituras en prod sin cuidado).
- **`pg_stat_statements`** para las consultas más costosas; `auto_explain` para capturar planes lentos.
- **Autovacuum**: no lo desactives. Vigila `pg_stat_user_tables` (dead tuples) y el bloat; un `IN`/`UPDATE` masivo necesita `VACUUM`.

## JSONB

```sql
-- Consulta y filtro por contenido, con índice GIN
CREATE INDEX idx_app_products_attrs ON app_products USING gin (attrs jsonb_path_ops);
SELECT id, attrs->>'color' AS color FROM app_products WHERE attrs @> '{"color":"red"}';
```

Operadores: `->`/`->>` (campo como json/texto), `@>` (contiene), `?` (clave existe). Indexa con GIN solo si filtras por el JSON con frecuencia.

## Esquemas y convenciones

- `search_path` importa: califica (`public.tabla`) en migraciones y scripts para no depender del `search_path` del usuario.
- Los identificadores **sin citar se pasan a minúsculas**; cita (`"CamelCase"`) solo si realmente lo necesitas.
- Prefijo de tablas por proyecto (p. ej. `app_`) para poder aislar/dropear en tests contra una BD compartida.

## Extensiones útiles

- `pgcrypto` (hashes), `citext` (texto case-insensitive), `pg_trgm` (búsqueda por similitud con GIN), `uuid-ossp`.

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| Insertar en columna `GENERATED ALWAYS` | `ERROR: cannot insert into column` | Dejar que el motor lo genere (u `OVERRIDING SYSTEM VALUE`) |
| `ON CONFLICT` sin `UNIQUE` | Error de "no matching constraint" | Definir la restricción única antes |
| `CREATE INDEX` sin `CONCURRENTLY` en prod | Bloquea escrituras | `CONCURRENTLY` (fuera de transacción) |
| Transacción larga | Bloquea vacuum → bloat | Transacciones cortas |
| `timestamp` sin zona | Ambigüedad de horario | `timestamptz` + UTC |
| `json` en vez de `jsonb` para filtrar | No indexable con GIN / lento | `jsonb` |
| `char(n)` | Padding con espacios | `text`/`varchar` |
