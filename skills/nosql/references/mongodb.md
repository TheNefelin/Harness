# MongoDB — referencia

> Documental. Complementa `nosql/SKILL.md`.

> **Frescura (verificado 2026-10-17):** drivers Python para MongoDB: `PyMongo` (sync) y la API async **`AsyncMongoClient`** (GA en `pymongo`). **`Motor` está obsoleto**: deprecado el 2025-05-14, EOL el 2026-05-14, soporte final el 2027-05-14. Fuente: `mongodb.com/docs/drivers/motor/` y la guía de migración `mongodb.com/docs/languages/python/pymongo-driver/current/reference/migration/`.

## Modelo

- **Base de datos → colecciones → documentos** (BSON). Cada documento tiene `_id` (por defecto `ObjectId`, único e indexado).
- **Embed vs. reference**:
  - **1-a-1** y **1-a-pocos con tope** → embeber (una lectura trae todo).
  - **1-a-muchos sin tope** (historial, filas crecientes) → referenciar por `_id`.
  - **muchos-a-muchos** → referencias (o arrays de `_id` acotados).
- No existe JOIN barato como en SQL: si necesitas muchos `$lookup`, probablemente el modelo o el motor no corresponden.
- Valida la forma con **`$jsonSchema`** (`collMod` con `validator`) en vez de confiar en la disciplina del código.

## Índices

- El `_id` ya está indexado. El resto, por acceso.
- **Compuestos**: importan el orden y la dirección. Regla **ESR**: primero **E**quality, luego **S**ort, después **R**ange.
- Un índice multikey (sobre array) indexa cada elemento del array.
- **TTL** (`expireAfterSeconds`) para documentos efímeros; **parciales** (`partialFilterExpression`) para subconjuntos.
- Diagnostica con `explain("executionStats")`: busca `IXSCAN` (usa índice), no `COLLSCAN`.

```javascript
db.orders.createIndex({ customerId: 1, status: 1, createdAt: -1 });
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
```

## Consultas

- Filtros con **operadores** (`$eq`, `$in`, `$gte`, `$regex`), proyección para traer solo lo necesario.
- **Aggregation pipeline** para agrupaciones/transformaciones: `$match` temprano (usa índices), luego `$group`, `$sort`, `$project`. `$lookup` para traer de otra colección (caro; usalo con filtro selectivo).
- `countDocuments` (consistente) vs. `estimatedDocumentCount` (rápido, aproximado).

## Escritura y concurrencia

- `updateOne`/`findOneAndUpdate` son **atómicos por documento**. Usa `findOneAndUpdate` con filtro + `$set` para updates atómicos sin leer-y-escribir.
- **Transacciones multimodocumento** (requieren replica set/sharded): úsalas cuando realmente necesitas atomicidad entre documentos; no son gratis (rendimiento, retries). Prefiere diseño que evite la necesidad.
- **Concurrencia optimista**: campo `version` en el filtro del update (`{ _id, version: v }`) e incrementarlo; si no coincide, reintenta.

## Drivers

- **.NET**: `MongoDB.Driver` (async: `IMongoCollection<T>`), mapeo con atributos o `BsonClassMap`; proyecciones tipadas con `Builders<T>.Projection`.
- **Python**: `PyMongo` (sync) o **`AsyncMongoClient`** (API async de `pymongo`; la que debe usar FastAPI). **`Motor` está obsoleto** (deprecado 2025-05-14, EOL 2026-05-14): solo como tecnología heredada a migrar. La API async usa `asyncio` nativo (no thread pool) y **no es thread-safe**: no compartas el cliente entre hilos ni event loops.

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
