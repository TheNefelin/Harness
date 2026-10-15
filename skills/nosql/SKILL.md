---
name: nosql
description: Bases de datos NoSQL: MongoDB (documental), Azure Cosmos DB, Redis (clave-valor/caché) y Amazon DynamoDB. Usar al modelar, consultar u operar datos no relacionales: documentos, caché, colecciones, claves de partición, consistencia o patrones de acceso. NO para relacional/SQL ('sql') ni el acceso a datos desde el ORM/código ('dotnet'/'fastapi').
---

# Bases de datos NoSQL — Patrón senior

> Criterio transversal para MongoDB, Azure Cosmos DB, Redis y DynamoDB. Lo común va en este archivo; el detalle por motor, en `references/`.

**Referencias** (se leen bajo demanda, rutas relativas a esta skill): `references/mongodb.md`, `references/cosmosdb.md`, `references/redis.md`, `references/dynamodb.md`.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Base relacional, integridad referencial fuerte, transacciones multi-tabla, consultas ad-hoc | `sql` |
| Cómo consultar desde el ORM/SDK del lenguaje (Dapper, EF Core, SQLAlchemy, drivers) | `dotnet` / `fastapi` |

Usa NoSQL solo cuando el modelo de datos o el patrón de acceso lo justifiquen; si dudas, el relacional (`sql`) suele ser la elección correcta.

> **Alcance y frescura:** este skill cubre patrones de arquitectura y acceso (particionado, consistencia, idempotencia), no atados a versiones. Los detalles de API, límites y cuotas deben verificarse contra la documentación oficial vigente de cada motor.

---

## 1. Elegir NoSQL con criterio

- **No por moda.** Usa NoSQL cuando el modelo de datos o el patrón de acceso lo justifique: documentos con estructura variable, altísimo volumen/throughput con acceso por clave, caché, o esquemas que cambian mucho.
- **Relacional por defecto** para datos transaccionales con relaciones e integridad (ver skill `sql`). Si el requisito es integridad referencial fuerte y consultas ad-hoc, NoSQL suele ser la elección equivocada.
- **No es "sin esquema"**: es esquema **implícito** en el código. Igual hay que definir la forma de los datos, versionarla y validarla.

## 2. Modelado guiado por el acceso (query-first)

- **Primero los patrones de acceso, después el modelo.** A diferencia del relacional (modelas entidades y normalizas), en NoSQL partes de *cómo vas a consultar*.
- **Embed vs. reference** (documentales): embebe lo que se lee junto y no crece sin límite; referencia lo que es grande, compartido o cambia de forma independiente. Una lista embebida **sin tope** es un anti-patrón.
- **Desnormalización deliberada**: duplicar datos para leer en una sola operación es correcto aquí, siempre que definas **cómo mantienes la copia** consistente (al escribir, o por proceso).
- **Clave de partición** (Cosmos DB/DynamoDB): es la decisión más importante. Busca alta cardinalidad y acceso uniforme (evita "hot partitions"); si no existe una clave natural, usa una **sintética** (p. ej. `tenant#bucket`).
- **Single-table design** (DynamoDB): modelar varias entidades en una tabla para resolver consultas con una sola lectura; solo cuando las consultas sean conocidas y estables.

## 3. Decisiones comunes

- **Consistencia**: entiende el espectro (fuerte ↔ eventual). Eventual es más rápida y disponible, pero exige tolerar lecturas desactualizadas; no la uses donde necesitas leer lo que acabas de escribir sin condición.
- **Idempotencia**: los reintentos son la norma; las escrituras deben poder repetirse sin duplicar (claves únicas, upsert, tokens de idempotencia).
- **Versionado de esquema**: agrega `schemaVersion`/campos nuevos con default; no rompas documentos viejos. Migra de forma perezosa o por proceso.
- **TTL** para datos efímeros (sesiones, caché, tokens): expiración nativa en vez de limpieza manual.
- **Índices**: en NoSQL el índice se paga por escritura y algunos se declaran aparte (GSI/containers). Indexa por los accesos reales, no "todo".
- **Concurrencia optimista**: control de versión (ETag, `_etag`, `version`) para evitar lost updates.
- **Límites por ítem**: conoce el techo de cada motor (tamaño de documento/ítem, throughput por partición) y diseña dentro de él.

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
| Upsert sin índice único | Dos escrituras concurrentes crean duplicados | Índice único en la clave lógica + upsert |

## 5. Patrones copiables (Bad → Good)

**Embed vs. reference** (documental — referencia lo que no tiene tope):
```javascript
// ❌ Bad: array embebido sin límite → el documento crece sin fin
{ _id: 1, name: "Pedido", lines: [ /* ...miles... */ ] }

// ✅ Good: lo que no tiene tope va en otra colección, con índice por orderId
{ _id: 1, customerId: 10 }                     // orders
{ orderId: 1, productId: 7, qty: 2 }           // order_lines
```

**Query vs. Scan** (DynamoDB — `Scan` recorre toda la tabla):
```javascript
// ❌ Bad: caro y lento en producción
await ddb.scan({ TableName: "app_items" });

// ✅ Good: Query por la clave (partition + sort)
await ddb.query({
  TableName: "app_items",
  KeyConditionExpression: "pk = :pk AND begins_with(sk, :prefix)",
  ExpressionAttributeValues: { ":pk": "TENANT#42", ":prefix": "ORDER#" },
});
```

**Clave de partición** (DynamoDB/Cosmos — debe tener alta cardinalidad):
```text
❌ Bad:  pk = status ("pending" | "done")      → pocas claves → hot partition
✅ Good: pk = "T42#2026-10"                    → alta cardinalidad, acceso uniforme
```

**Upsert idempotente** (reintentos seguros, no duplican):

> Requiere un **índice único** en el campo que identifica el registro (`token`): sin él, dos upserts concurrentes pueden crear dos documentos.

```javascript
// ✅ Good: MongoDB — con índice único en `token`
// db.app_sessions.createIndex({ token: 1 }, { unique: true })
await db.collection("app_sessions").updateOne(
  { token: token },
  { $set: { updatedAt: new Date() }, $setOnInsert: { createdAt: new Date() } },
  { upsert: true }
);
```

**Caché-aside con TTL** (Redis como acelerador, no como fuente de verdad):
```text
✅ Good: leer caché → si miss, leer de la BD y SET product:42 EX 300
❌ Bad:  escribir solo en Redis y tratarlo como la fuente de verdad
```

## 6. Checklist

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

## 7. Fuentes

- **Clave de partición y Query vs Scan**: AWS DynamoDB docs (`docs.aws.amazon.com`).
- **Embed vs reference y modelado**: MongoDB docs (`mongodb.com/docs`).
- **Caché-aside y TTL**: Redis docs (`redis.io/docs`).
