# AWS — control y optimización de costes

> Las cifras de free tier cambian; este archivo es sobre **cómo gobernar el gasto**, que es estable.

## Antes de desplegar

1. **Presupuesto** en `Billing → Budgets` (fijo mensual, p. ej. USD 1–5) con alertas al **50 %** y **100 %**.
2. **Alertas de Free Tier** activadas para cada servicio relevante.
3. **Cost Allocation Tags** obligatorios (`project`, `env`, `owner`) desde el día 1: sin tags no hay desglose.
4. **Pricing Calculator** para estimar antes de crear infraestructura nueva.

## Durante el uso

| Fuente de gasto | Cómo evitarlo |
|-----------------|---------------|
| **Egress (salida de datos)** | Es la trampa clásica: no es gratis en S3/EC2. Usar CloudFront cuando convenga y no copiar datos de ida y vuelta entre regiones |
| **NAT Gateway** | Cobra por hora **y** por GB; en dev casi nunca hace falta (Internet Gateway o VPC endpoints) |
| **Load Balancers** | Cobra por hora aunque no tenga tráfico; eliminar en dev |
| **EBS sin usar / snapshots** | Discos desasociados y snapshots viejos siguen costando; podarlos |
| **IPs elásticas sin asociar** | Generan cargo si no están adjuntas a una instancia en uso |
| **Regiones/características premium** | Elegir región barata y no activar features "enterprise" sin necesidad |
| **Recursos olvidados** | Todo lo que esté "apagado pero creado" factura (almacenamiento, LB, IP) |

## Herramientas de diagnóstico

- **Cost Explorer**: evolución y desglose por servicio/región/tag; detectar picos.
- **Cost Explorer → Right-size / RI & Savings Plans**: recomendaciones de dimensionado.
- **Trusted Advisor** (o **AWS Health Dashboard**): avisos de seguridad y coste.
- **`GetFreeTierUsage`**: consumo de free tier por servicio, programable.

## Optimización (cuando se paga de verdad)

- **Right-sizing** antes que Reserved Instances: casi siempre hay un tamaño más pequeño.
- **Savings Plans / Reserved Instances** solo para carga estable y predecible.
- **S3 Intelligent-Tiering** para datos de acceso impredecible; no pagar por el tier alto por costumbre.
- **Lambda**: ajustar memoria (el coste escala con ella) y tiempo de ejecución; evitar funciones calientes sin tráfico.

## Errores comunes

| Error | Consecuencia |
|-------|--------------|
| "Apago la VM y ya no pago" | Sigue cobrando el almacenamiento, la IP y el LB |
| "El free tier me cubre" | Solo los servicios/montos marcados y solo dentro del plazo |
| "No pongo budget porque es un proyecto pequeño" | El presupuesto pequeño es exactamente donde duele una sorpresa |
| "Dejo el NAT en dev" | Coste fijo alto sin utilidad |
