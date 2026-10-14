# OCI Always Free — límites y cobros

> **Verificado 2026-10-14** contra `docs.oracle.com/.../Always_Free_Resources.htm`. El detalle exacto cambia; la fuente oficial prevalece.

## Límites Always Free

| Recurso | Límite | Notas |
|---------|--------|-------|
| Compute ARM (`VM.Standard.A1.Flex`) | **2 OCPU + 12 GB RAM** totales | ≈1.500 OCPU-h y 9.000 GB-h/mes; es **por cuenta** |
| Compute x86 (`VM.Standard.E2.1.Micro`) | 2 instancias | 1/8 OCPU, 1 GB cada una |
| Block Volume | 200 GB (boot + datos) | Boot volume mínimo ~47 GB por instancia A1 |
| Backups de volúmenes | 5 | Más = cargo |
| Object Storage | ~20 GB | Con ciclo de vida a Archive conviene |
| Egress (salida) | 10 TB/mes | Generoso comparado con otros |
| Load Balancer | 1 flexible | 10 Mbps |

## Cambio de 2026

- Oracle **redujo** el ARM Always Free: de 4 OCPU / 24 GB a **2 OCPU / 12 GB**.
- Las cuentas Always Free debieron ajustarse **antes del 2026-08-18**; las que excedían podían ser terminadas.
- Se rumorea que cuentas **Pay As You Go** mantienen 4 OCPU / 24 GB sin costo: **sin confirmación oficial**, no planificar sobre eso.

## Reclamo por inactividad

Oracle puede **borrar** instancias Always Free si, durante 7 días seguidos:

- CPU percentil 95 < **20 %**
- Red < **20 %**
- Memoria < **20 %** (solo formas A1)

**Mitigación**: mantener actividad mínima continua (un sitio con visitas o un cron ligero). No depender de una VM apagada la mayor parte del tiempo.

## Recursos que siguen cobrando aunque "apagues" la VM

- Discos en bloque adicionales (más allá de lo incluido)
- **IPs públicas reservadas sin adjuntar**
- Snapshots por encima de los 5 gratuitos
- Volúmenes **fuera de la home region**
- Load Balancers adicionales al gratuito
- Bases de datos gestionadas de pago

## Errores comunes

| Error | Consecuencia / solución |
|-------|-------------------------|
| Crear una VM sin "Always Free Eligible" | Facturación inmediata; no crear |
| Exceder 2 OCPU / 12 GB en A1 | Terminan las instancias; revisar el total de la cuenta |
| "Out of capacity" en regiones populares | Reintentar en horario valle, otro AD, o pasar a PAYG |
| `docker compose down -v` | Borra volúmenes (BD y archivos); no usarlo sin querer borrar |
| Confiar solo en la nube | Descargar respaldos fuera de la VM y probar la restauración |

## Costes reales (si sales de free)

- **Compute**: OCPU/mes (A1 y x86) + RAM GB/mes; las micro x86 son las más baratas.
- **Block Volume**: GB-mes y IOPS provisionados; los snapshots facturan GB almacenados.
- **Object Storage**: GB-mes (estándar) y almacenamiento frío más barato.
- **Egress**: GB transferidos (el tramo inicial gratis es amplio).
- Siempre revisar **Billing & Cost Management → Cost Analysis** tras crear cualquier recurso nuevo.
