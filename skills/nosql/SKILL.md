---
name: nosql
description: Bases de datos NoSQL: MongoDB (documental), Azure Cosmos DB, Redis (clave-valor/caché) y Amazon DynamoDB. Usar cuando se modele, consulte u opere datos no relacionales: documentos, caché, colecciones, claves de partición, consistencia o patrones de acceso.
---

# Bases de datos NoSQL — Patrón senior

> Criterio transversal para MongoDB, Azure Cosmos DB, Redis y DynamoDB. Lo común va en este archivo; el detalle por motor, en `references/`.

**Referencias** (se leen bajo demanda, rutas relativas a esta skill): `references/mongodb.md`, `references/cosmosdb.md`, `references/redis.md`, `references/dynamodb.md`.

---

## 1. Elegir NoSQL con criterio

- **No por moda.** Usá NoSQL cuando el modelo de datos o el patrón de acceso lo justifique: documentos con estructura variable, altísimo volumen/throughput con acceso por clave, caché, o esquemas que cambian mucho.
- **Relacional por defecto** para datos transaccionales con relaciones e integridad (ver skill `sql`). Si el requisito es integridad referencial fuerte y consultas ad-hoc, NoSQL suele ser la elección equivocada.
- **No es "sin esquema"**: es esquema **implícito** en el código. Igual hay que definir la forma de los datos, versionarla y validarla.

## 2. Modelado guiado por el acceso (query-first)

- **Primero los patrones de acceso, después el modelo.** A diferencia del relacional (modelás entidades y normalizás), en NoSQL partís de *cómo vas a consultar*.
- **Embed vs. reference** (documentales): embebé lo que se lee junto y no crece sin límite; referenciá lo que es grande, compartido o cambia de forma independiente. Una lista embebida **sin tope** es un anti-patrón.
- **Desnormalización deliberada**: duplicar datos para leer en una sola operación es correcto aquí, siempre que definas **cómo mantenés la copia** consistente (al escribir, o por proceso).
- **Clave de partición** (Cosmos DB/DynamoDB): es la decisión más importante. Buscá alta cardinalidad y acceso uniforme (evitá "hot partitions"); si no existe una clave natural, usá una **sintética** (p. ej. `tenant#bucket`).
- **Single-table design** (DynamoDB): modelar varias entidades en una tabla para resolver consultas con una sola lectura; solo cuando las consultas sean conocidas y estables.

## 3. Decisiones comunes

- **Consistencia**: entendé el espectro (fuerte ↔ eventual). Eventual es más rápida y disponible, pero exige tolerar lecturas desactualizadas; no la uses donde necesitás leer lo que acabás de escribir sin condición.
- **Idempotencia**: los reintentos son la norma; las escrituras deben poder repetirse sin duplicar (claves únicas, upsert, tokens de idempotencia).
- **Versionado de esquema**: agregá `schemaVersion`/campos nuevos con default; no rompas documentos viejos. Migrá de forma perezosa o por proceso.
- **TTL** para datos efímeros (sesiones, caché, tokens): expiración nativa en vez de limpieza manual.
- **Índices**: en NoSQL el índice se paga por escritura y algunos se declaran aparte (GSI/containers). Indexá por los accesos reales, no "todo".
- **Concurrencia optimista**: control de versión (ETag, `_etag`, `version`) para evitar lost updates.
- **Límites por ítem**: conocé el techo de cada motor (tamaño de documento/ítem, throughput por partición) y diseñá dentro de él.

## 4. Anti-patrones

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| Modelar como en SQL (normalizar todo) | Consultas que necesitan N round-trips | Modelar por acceso; embeber lo que se lee junto |
| Array embebido sin límite | Documento que crece sin fin; degrada | Referenciar / acotar tamaño |
| Clave de partición de baja cardinalidad | Hot partition, throttling | Alta cardinalidad o clave sintética |
| `Scan` en producción | Coste y latencia desproporcionados | Diseñar claves e índices para `Query` |
| Confiar en consistencia fuerte donde es eventual | Lecturas desactualizadas "aleatorias" | Asumir la semántica; leer de la fuente primaria si es crítico |
| Caché como fuente de verdad | Pérdida de datos al expirar/limpiar | Redis = acelerador; la verdad vive en la BD |
| Índices "por si acaso" | Escrituras más caras; throttling | Indexar por accesos reales |
| Sin control de versión en updates | Lost updates bajo concurrencia | ETag/versioning / transacción |

## 5. Checklist

- [ ] Se eligió NoSQL por un requisito real (no por preferencia)
- [ ] Patrones de acceso definidos **antes** del modelo
- [ ] Decisión embed vs. reference justificada (sin arrays sin tope)
- [ ] Clave de partición con buena cardinalidad y acceso uniforme
- [ ] Consultas resueltas por `Query`/clave (no `Scan`)
- [ ] Consistencia asumida explícitamente
- [ ] Escrituras **idempotentes** (reintentos seguros)
- [ ] Versionado de esquema (`schemaVersion` o equivalente)
- [ ] TTL en datos efímeros
- [ ] Índices por acceso real (coste de escritura considerado)
- [ ] Control de concurrencia optimista donde aplica
