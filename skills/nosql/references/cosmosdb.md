# Azure Cosmos DB — referencia (API Core/SQL)

> Documental JSON con particionado. Complementa `nosql/SKILL.md`.

## Modelo y particionado

- **Account → databases → containers → items** (JSON). Un container es la unidad de escalado y de particionado.
- **Clave de partición**: la decisión de diseño central. Alta cardinalidad y distribución uniforme de lecturas/escrituras. Una clave de baja cardinalidad (p. ej. `status`) concentra carga (**hot partition**) y provoca throttling (429).
- Cada **partición lógica** (un valor de la clave) tiene un límite de almacenamiento (~20 GB): una clave que agrupe demasiados datos revienta ese techo. Claves **jerárquicas** ayudan a repartir.
- **Lectura por punto** (`id` + partition key) es la operación más barata; todo lo demás cuesta más RU.

## Unidades de rendimiento (RU/s)

- Todas las operaciones se miden en **Request Units**: un punto de lectura = 1 RU (aprox.), una escritura y una consulta cuesta más.
- Modalidades: **provisioned** (RU/s fijas), **autoscale** (mín–máx) o **serverless** (pago por uso, sin picos garantizados). Elige según el tráfico.
- **Optimiza consultas**: filtra siempre por la partition key para evitar consultas **cross-partition** (recorren todas las particiones → caro). Limita el resultado (`TOP`), evita `SELECT *`.

## Consistencia

Cinco niveles, de más fuerte a más débil: **Strong, Bounded Staleness, Session, Consistent Prefix, Eventual**.

- **Session** (el más usado): consistente dentro de una sesión del cliente; buena combinación de rendimiento y frescura.
- Strong no está disponible con multi-región de escritura a escala. Elige el nivel más débil que el negocio tolere, no el más fuerte "por las dudas".

## Índices

- Por defecto **se indexa todo automáticamente** (a diferencia de Mongo). Si no lo necesitas, ajusta la **indexing policy** para excluir rutas y ahorrar RU en escritura.
- **Índices compuestos** son necesarios para `ORDER BY` por más de un campo y para varios filtros.
- No hay índices creados "a mano" por consulta: se gobierna la política del container.

## Escritura y concurrencia

- **Concurrencia optimista** con **ETag**: envía `If-Match` con el `_etag` que leíste; si el ítem cambió, la escritura falla (409) y la resuelves.
- **TTL** a nivel container o ítem (`ttl` en segundos) para expiración automática.
- **Change feed** para reaccionar a cambios (procesos, sincronización, event sourcing).

## Driver (.NET)

- `Microsoft.Azure.Cosmos` (`CosmosClient`): crear el container con `PartitionKey`, definir la `IndexingPolicy`, y usar `ReadItemAsync` (punto) antes que queries. POCOs mapeados por atributo o por `CosmosSerializer`.

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| Clave de partición de baja cardinalidad | Hot partition, 429 | Alta cardinalidad / sintética |
| Consulta sin partition key | Cross-partition, coste alto | Filtrar por la clave o usar el `id` |
| Dejar la indexación por defecto con esquema grande | Escrituras caras en RU | Excluir rutas no consultadas |
| `ORDER BY` multi-campo sin índice compuesto | Query no soportada / degradada | Definir índice compuesto |
| Asumir consistencia fuerte | Lecturas desfasadas o costo | Elegir el nivel a conciencia |
| Actualizar sin `_etag` | Lost updates | `If-Match` con ETag |
| Diseñar como relacional | Consultas y particionado ineficientes | Modelar por acceso |
