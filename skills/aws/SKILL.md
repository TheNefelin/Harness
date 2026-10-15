---
name: aws
description: Arquitectura, seguridad y costes en AWS (EC2, S3, Lambda, IAM, VPC) incluido el Free Tier. Usar al diseñar, desplegar o revisar infraestructura o servicios en Amazon Web Services: instancias, almacenamiento, serverless, IAM, redes o control de costes. NO para Azure ('azure') ni Oracle Cloud ('oci') ni solo contenedores ('docker'/'kubernetes').
---

# AWS — Patrón senior

> Decisión de arquitectura, seguridad de identidad y control de costes en Amazon Web Services. Anti-patrones y patrones; no es un tutorial de consola.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Infraestructura en Microsoft Azure | `azure` |
| Infraestructura en Oracle Cloud (OCI) | `oci` |
| Solo contenerizar / orquestar | `docker` / `kubernetes` |
| Pipeline de CI/CD (OIDC hacia AWS) | `github-actions` |

> **Frescura (verificado 2026-10-14):** el Free Tier de AWS **cambió para cuentas creadas desde el 2025-07-15**: ya no son 12 meses de servicios, sino un plan **Free con créditos** (6 meses) o un plan **Paid**; los servicios **Always Free (30+)** siguen vigentes en ambos planes. Las cuentas previas conservan el modelo legacy de 12 meses. Fuentes: `aws.amazon.com/free`, `docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-FAQ.html`.

## Modelos de cuenta (2026)

| | Plan **Free** | Plan **Paid** | Legacy (cuenta < 2025-07-15) |
|---|---|---|---|
| Créditos | USD 100 al crear + hasta USD 100 más | Igual, al crear | — |
| Duración | **6 meses** o se agotan los créditos (lo que primero) | Créditos vencen a los 12 meses del alta | Free Tier de **12 meses** |
| Acceso a servicios | Solo un **subconjunto** (evita agotar créditos) | **Toda** la cartera | Cartera habitual |
| Si te pasas | **No se factura**: la cuenta se cierra | Facturación on-demand | **Facturación on-demand automática** |
| Al cerrar/terminar | 90 días para pasar a Paid y rescatar datos | — | — |

- **Always Free**: 30+ servicios con límite mensual, mientras seas cliente, en ambos planes (Lambda, DynamoDB, CloudFront, SQS/SNS, CloudWatch, Cognito).
- **Ojo con la etiqueta "Free"**: `S3` (5 GB), `API Gateway` (1 M REST) y las instancias EC2/RDS **no** son Always Free — son ofertas de **12 meses** o consumen créditos del plan Free. Al vencer, facturan aunque el recurso siga creado.
- **Límite de región**: el Free Tier **no aplica** en China (ZHY/BJS) ni, salvo excepciones (Lambda), en GovCloud. El uso se acumula **en todas las regiones**.
- Verificar siempre el detalle en la fuente oficial antes de desplegar: los límites y las condiciones cambian con frecuencia.

## Reglas para no facturar

1. **Antes de crear cualquier recurso**, comprobar en la consola que aparece **"Free Tier eligible"** y la región elegida tenga disponibilidad.
2. **Budget obligatorio el día 1**: `Billing → Budgets` con alertas al 50 % y 100 % (también sirve para ganar los USD 100 adicionales del plan Free).
3. **Alertas de Free Tier**: `Billing → Free Tier` / API `GetFreeTierUsage` para ver consumo por servicio y mes.
4. **No mezclar planes a la ligera**: pasar de Free a Paid mantiene los créditos hasta 12 meses desde el alta, pero activa facturación real por encima de ellos.
5. **Recursos sin uso = facturación**: instancias apagadas con disco, IPs elásticas sin asociar, snapshots fuera de límite, load balancers y **NAT gateways** siguen costando.
6. **Egress es la trampa clásica**: salida de S3/EC2 no es gratis; usar CloudFront (tiene 1 TB/mes Always Free) cuando convenga.

## Decisiones y convenciones

- **IAM por roles, nunca usuarios con claves largas**: least privilege, MFA en root, sin `*:*`, y **OIDC desde CI/CD** en lugar de access keys.
- **Cost Allocation Tags**: etiquetar todo desde el origen (`project`, `env`, `owner`) — sin tags no hay desglose de costes.
- **Región fija y barata** en dev; no desplegar en varias regiones sin motivo.
- **Free tier → Always Free primero**: si el objetivo es costo 0 indefinido, armar con **Lambda + DynamoDB + API Gateway + Cognito** (todo Always Free) en vez de EC2 (que es de corta duración o del plan).
- **IaC por defecto** (Terraform o CloudFormation): reproducibilidad y auditoría de qué existe y qué factura.
- **Serverless o instancias pequeñas** para empezar; escalar solo con métricas que lo justifiquen.

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| Crear recursos sin verificar "Free Tier eligible" | Facturación inmediata | Comprobar etiqueta + región antes de crear |
| Olvidar el fin de la prueba/plan Free | El 12-avo mes (legacy) o el cierre del plan arranca cobrando | Alertas de fecha + budget antes de que venza |
| `0.0.0.0/0` en Security Group sobre 22/3389 | Exposición total | Origen restringido o SSM Session Manager |
| Claves de acceso hardcodeadas en CI | Rotación imposible, filtración grave | Rol + OIDC |
| S3 público o sin bloqueo | Fuga de datos | Bloquear acceso público + política |
| Dejar EC2/EBS/IPs apagados "por si acaso" | Cobro continuo | Terminar lo que no se use; IP elástica sin asociar cobra |
| NAT Gateway 24/7 en dev | Cobro fijo alto (hora + GB) | Para free tier, salir por Internet Gateway o VPC endpoints |
| Sin budget | Sorpresa de factura | Budget con alertas al 50 % y 100 % |

## Patrones

### Stack Always Free (coste 0 indefinido)

```text
Lambda + Function URL (1M req + 400K GB-s/mes) ──► DynamoDB (25 GB + 200M req/mes)
Cognito (50.000 MAU/mes) · CloudFront (1 TB salida/mes) · SQS/SNS (1M/mes)
```

> **API Gateway y S3 no entran aquí**: sus 1 M llamadas y 5 GB son ofertas de **12 meses** (o consumen créditos). Para coste 0 perpetuo usa **Lambda Function URL** en vez de API Gateway, y CloudFront en vez de servir S3 directo.

### Budget mínimo por consola/CLI

```bash
aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget '{"BudgetName":"mensual","BudgetLimit":{"Amount":"5","Unit":"USD"},"BudgetType":"COST","TimeUnit":"MONTHLY"}' \
  --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":50,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"tu@correo.com"}]}]'
```

## Checklist

- [ ] Región correcta y recurso marcado **Free Tier eligible**
- [ ] Budget creado con alertas al 50 % y 100 %
- [ ] Alertas de consumo de Free Tier activas
- [ ] IAM least privilege + MFA en root, sin claves estáticas en CI (OIDC)
- [ ] S3 sin acceso público; Security Group sin `0.0.0.0/0` en SSH/RDP
- [ ] Tags de cost allocation aplicados
- [ ] Recursos sin uso terminados (EBS, IPs elásticas, snapshots, LB)
- [ ] Fecha de vencimiento del plan/Free Tier anotada y recordada

## Fuentes

- **AWS Free Tier**: `https://aws.amazon.com/free/` y `https://aws.amazon.com/free/free-tier-faqs/`
- **AWS Free Tier FAQ (docs)**: `https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-FAQ.html`
- **EC2 Free Tier (por fecha de cuenta)**: `https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html`
