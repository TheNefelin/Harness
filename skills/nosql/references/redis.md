# Redis — referencia (clave-valor / caché)

> Clave-valor en memoria. Complementa `nosql/SKILL.md`.

## Cuándo usarlo

- **Caché** (cache-aside), **sesiones**, **rate limiting** (contadores), **colas/locks** ligeros, ranking (sorted sets). No es una fuente de verdad transaccional por defecto.

## Estructuras

| Estructura | Uso típico |
|------------|-----------|
| `String` | Caché de valores, contadores (`INCR`) |
| `Hash` | Objeto con campos (asesor: guardar JSON en un string) |
| `List` | Colas simples (push/pop) |
| `Set` | Membresías únicas |
| `Sorted Set (ZSET)` | Rankings, rate limiting por ventana, colas con prioridad |
| `Stream` | Colas con consumidores y ack (más robusto que List) |

## Expiración y memoria

- **`TTL` por clave** (`EXPIRE`/`SETEX`): siempre pon expiración en caché, salvo dato que realmente es permanente.
- Configura una **eviction policy** (p. ej. `allkeys-lru`) para que bajo presión libere memoria en vez de empezar a rechazar escrituras.
- No guardes valores gigantes ni colecciones sin límite: es memoria RAM, cara.

## Patrones

- **Cache-aside**: leer caché → si falla, leer la fuente → escribir en caché con TTL. Define **invalidación** (borrar la clave al actualizar el dato).
- **Write-through** cuando necesitas que la caché se actualice junto con la escritura.
- **Atomicidad**: operaciones multi-clave con **Lua** (`EVAL`); `SET key value NX EX n` para locks simples (`SETNX` + expiración, nunca `SETNX` sin TTL). Evita locks distribuidos complejos salvo necesidad real.
- **Rate limiting**: contador con `INCR` + `EXPIRE`, o ZSET por ventana deslizante.
- **Idempotencia**: token con `SET token 1 NX EX <ttl>` para procesar una operación una sola vez.

## Persistencia

- **RDB** (snapshots) y **AOF** (log de operaciones). Ajusta según cuánto puedes perder; aun así, trata Redis como caché y no como base de datos duradera salvo configuración deliberada.

## Gotchas

| Gotcha | Problema | Solución |
|--------|----------|----------|
| `KEYS *` en producción | Bloquea el servidor | `SCAN` con cursor |
| `SETNX` sin `TTL` | Lock permanente si el proceso muere | `SET … NX EX` |
| Clave sin expiración | Memoria que crece sin control | `TTL` en todo dato cacheado |
| Guardar bloques enormes | Consume RAM y bloquea | Acotar tamaño / comprimir |
| Usar Redis como fuente de verdad | Pérdida al evictar/reiniciar | Persistir en la BD; Redis acelera |
| Invalidar mal la caché | Datos obsoletos | Definir política de invalidación |

## Driver (.NET)

`StackExchange.Redis` (`IConnectionMultiplexer` compartido, singleton). Usa operaciones async y `IDatabase` reutilizable.
