# MongoDB — referencia

> Documental. Complementa `nosql/SKILL.md`.

## Modelo

- **Base de datos → colecciones → documentos** (BSON). Cada documento tiene `_id` (por defecto `ObjectId`, único e indexado).
- **Embed vs. reference**:
  - **1-a-1** y **1-a-pocos con tope** → embeber (una lectura trae todo).
  - **1-a-muchos sin tope** (historial, filas crecientes) → referenciar por `_id`.
  - **muchos-a-muchos** → referencias (o arrays de `_id` acotados).
- No existe JOIN barato como en SQL: si necesitás muchos `$lookup`, probablemente el modelo o el motor no corresponden.
- Validá la forma con **`$jsonSchema`** (`collMod` con `validator`) en vez de confiar en la disciplina del código.

## Índices

- El `_id` ya está indexado. El resto, por acceso.
- **Compuestos**: importan el orden y la dirección. Regla **ESR**: primero **E**quality, luego **S**ort, después **R**ange.
- Un índice multikey (sobre array) indexa cada elemento del array.
- **TTL** (`expireAfterSeconds`) para documentos efímeros; **parciales** (`partialFilterExpression`) para subconjuntos.
- Diagnossticá con `explain("executionStats")`: buscá `IXSCAN` (usa índice), no `COLLSCAN`.

```javascript
db.orders.createIndex({ customerId: 1, status: 1, createdAt: -1 });
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
```

## Consultas

- Filtros con **operadores** (`$eq`, `$in`, `$gte`, `$regex`), proyección para traer solo lo necesario.
- **Aggregation pipeline** para agrupaciones/transformaciones: `$match` temprano (usa índices), luego `$group`, `$sort`, `$project`. `$lookup` para traer de otra colección (caro; usalo con filtro selectivo).
- `countDocuments` (consistente) vs. `estimatedDocumentCount` (rápido, aproximado).

## Escritura y concurrencia

- `updateOne`/`findOneAndUpdate` son **atómicos por documento**. Usá `findOneAndUpdate` con filtro + `$set` para updates atómicos sin leer-y-escribir.
- **Transacciones multimodocumento** (requieren replica set/sharded): usalas cuando realmente necesitás atomicidad entre documentos; no son gratis (rendimiento, retries). Preferí diseño que evite la necesidad.
- **Concurrencia optimista**: campo `version` en el filtro del update (`{ _id, version: v }`) e incrementarlo; si no coincide, reintentá.

## Drivers

- **.NET**: `MongoDB.Driver` (async: `IMongoCollection<T>`), mapeo con atributos o `BsonClassMap`; proyecciones tipadas con `Builders<T>.Projection`.
- **Python**: `PyMongo` (sync) o `Motor` (async, el que usa FastAPI).

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| Modelar como SQL (normalizar) | Muchos `$lookup`/round-trips | Embeber lo que se lee junto |
| Array embebido que crece sin fin | Documento enorme, límite de 16 MB | Referenciar |
| `$regex` sin anclaje | No usa índice | Prefijo anclado o índice de texto |
| `COLLSCAN` en `explain` | Recorre toda la colección | Crear índice para ese filtro/orden |
| Índice con orden equivocado | No sirve al `sort` | Respetar regla ESR y direcciones |
| Confiar en TTL para negocio | Borrado en ~60 s, no exacto | TTL para efímeros, no para reglas estrictas |
| Escrituras no idempotentes | Duplicados en reintentos | Upsert con clave única / `_id` propio |
