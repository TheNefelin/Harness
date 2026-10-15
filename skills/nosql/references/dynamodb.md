# Amazon DynamoDB — referencia

> Documental/clave-valor gestionado en AWS. Complementa `nosql/SKILL.md`.

## Modelo

- **Tabla → ítems → atributos**. Sin esquema fijo más allá de las claves.
- **Clave primaria**: solo **partition key** (PK) o **PK + sort key** (compuesta). La PK decide en qué partición cae el ítem y es la base del rendimiento.
- **Single-table design**: modelar varias entidades en una sola tabla, usando la PK/SK con prefijos (`USER#123`, `ORDER#456`) para resolver distintas consultas con una sola lectura. Potente pero exige conocer bien los accesos.

## Claves y acceso

- **`Query`** (por clave) es lo esperado y eficiente. **`Scan`** recorre toda la tabla → caro y lento; evitalo en producción.
- **GSI/LSI**: índices secundarios para consultar por otros atributos. Un GSI tiene su propia PK/SK y capacidad (costo aparte).
- **Hot partitions**: una PK de baja cardinalidad o acceso concentrado limita el throughput por partición. Diseña la clave con buena cardinalidad; si no existe, **clave sintética** (p. ej. `tenant#shard`).

## Capacidad y coste

- **On-demand** (pago por request) o **provisioned** (RCU/WCU fijos, con autoscaling). RCU depende de consistencia y tamaño del ítem.
- **Consistencia**: las lecturas son **eventualmente consistentes** por defecto; `ConsistentRead` da lectura fuerte a **mayor costo** en RCU.

## Escritura y concurrencia

- `PutItem`, `UpdateItem`, `DeleteItem`. **`ConditionExpression`** para escrituras condicionales (idempotencia, control de versión, "insertar si no existe").
- **Transacciones** (`TransactWriteItems`/`TransactGetItems`): hasta varias operaciones atómicas en una o más tablas; más caras y con límites.
- **TTL** con un atributo de expiración (borrado eventual, no exacto).
- **Streams**: cambios por ítem → procesamiento/reactividad.
- Concurrencia optimista con un atributo `version` en la `ConditionExpression`.

```json
// Update condicional: solo si la versión coincide (evita lost update)
{
  "TableName": "app",
  "Key": { "PK": { "S": "USER#1" } },
  "UpdateExpression": "SET #n = :n, version = version + :one",
  "ConditionExpression": "version = :v",
  "ExpressionAttributeNames": { "#n": "name" },
  "ExpressionAttributeValues": { ":n": { "S": "Ana" }, ":one": { "N": "1" }, ":v": { "N": "3" } }
}
```

## Límites

- Ítem máximo ~**400 KB** (contando nombres y tipos). Lo grande va a S3 con la referencia en DynamoDB.
- Sin joins; sin agregaciones ricas (usa GSI, contadores atómicos o un servicio aparte).

## Driver (.NET)

`AWSSDK.DynamoDBv2` (`AmazonDynamoDBClient`) o el **`DynamoDBContext`** del `AWSSDK.DynamoDBv2.DataModel` para mapeo de POCOs. Configura credenciales/región por el SDK (IAM, no en código).

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| `Scan` en el hot path | Caro y lento | Diseñar PK/GSI para `Query` |
| PK de baja cardinalidad | Throttling por hot partition | Clave sintética / alta cardinalidad |
| Olvidar el coste de GSI | Duplica capacidad | Provisionar/observar el GSI |
| Sin `ConditionExpression` | Lost updates / duplicados | Escritura condicional con `version` |
| Ítem enorme | Supera ~400 KB | Guardar en S3, referenciar |
| Asumir lectura fuerte | Datos obsoletos | `ConsistentRead` donde importe |
| Modelar relacional | Muchos round-trips | Single-table / desnormalizar |
