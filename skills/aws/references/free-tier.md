# AWS Free Tier — detalle por servicio

> Límites **verificados 2026-10-14**. Son volátiles: contrastar siempre con `https://aws.amazon.com/free/` antes de desplegar. La fuente oficial prevalece sobre este archivo.

## Always Free (mientras seas cliente; ambos planes)

| Servicio | Límite mensual |
|----------|----------------|
| **Lambda** | 1 M de peticiones + 400.000 GB-segundos (≈3,2 M de segundos) de compute |
| **DynamoDB** | 25 GB de almacenamiento + 200 M de solicitudes |
| **CloudFront** | 1 TB de salida + 10 M de peticiones HTTP/S |
| **SNS** | 1 M de publicaciones + 1.000 notificaciones por correo |
| **SQS** | 1 M de solicitudes |
| **CloudWatch** | 10 métricas propias + 10 alarmas + monitorización básica |
| **Cognito** | 50.000 MAU/mes |

> Los límites **se reinician el día 1 de cada mes**: no se acumulan ni se arrastran.

## Ofertas temporales — NO son Always Free

| Servicio | Límite mensual | Dónde aplica |
|----------|----------------|--------------|
| **S3** | 5 GB Standard + 20.000 GET + 2.000 PUT (la **salida/egress no es gratis**) | legacy (12 meses) / plan Free (consume créditos) |
| **API Gateway** | 1 M de llamadas **REST**/mes (HTTP APIs tienen oferta aparte) | legacy (12 meses) / plan Free (consume créditos) |

> En cuentas **nuevas (≥ 2025-07-15)** ya **no** existen tiers de "12 meses": la cobertura sale de los **créditos** y del **plan Free (6 meses)**. Los "12 meses" aplican solo a cuentas **legacy (< 2025-07-15)**. Al agotar créditos o vencer el plan/plazo, **empieza la facturación** aunque el recurso siga creado. Las instancias EC2/EBS/RDS elegibles (sección siguiente) también son ofertas temporales.

## Plan Free (créditos) y legacy de 12 meses

- **Plan Free (cuentas ≥ 2025-07-15)**: USD 100 al alta + hasta USD 100 completando tareas de onboarding (lanzar/terminar EC2, configurar RDS, desplegar una Lambda, probar Bedrock, crear un budget). Vence a los **6 meses** o al agotarse.
- **Plan Paid**: mismos créditos, vigentes hasta **12 meses** desde la alta; acceso completo; facturación real por encima.
- **Legacy (< 2025-07-15)**: 12 meses con límites por uso (p. ej. `t2.micro`/`t3.micro`); al terminar, **facturación automática** sin aviso destacado.

## Instancias y almacenamiento elegibles (cuentas nuevas)

- **EC2 "Free tier eligible"**: `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large`.
- **EBS**: volúmenes elegibles (`gp2`, `st1`, `sc1`, `standard` — verificar el listado vigente por fecha de cuenta).
- Las cuentas previas al 2025-07-15 ven `t2.micro`/`t3.micro` en el panel de Free Tier.

## Cómo seguir el consumo

| Vía | Qué da |
|-----|--------|
| Consola `Billing → Free Tier` | Uso del mes por servicio, con avisos "Exceeds Free Tier" y "End of month forecast" |
| API `GetFreeTierUsage` | Consumo programático por servicio y tipo de uso |
| `Billing → Credits` | Fecha de vencimiento de los créditos |
| `Budgets` | Alertas al 50 % y 100 % (requiere presupuesto configurado) |

## Getchas

- El uso se acumula **entre todas las regiones**: no se "reinicia" al cambiar de región.
- El plan Free **no está disponible** en China (ZHY/BJS) y es casi totalmente inexistente en GovCloud.
- Pasar de Free a Paid **no pierde** los créditos restantes (siguen hasta 12 meses desde el alta), pero empieza a facturarse por encima.
- Que un servicio sea "Free Tier eligible" **no** lo hace gratis para siempre: la mayoría son de 12 meses o de corta duración.
