# Azure — control y optimización de costes

> Las cantidades de free tier cambian; este archivo es sobre **gobernar el gasto**.

## Antes de desplegar

1. **Presupuesto** en `Cost Management → Budgets` (USD 1–5) con alertas al **50 %** y **100 %**.
2. **Límite de gasto (spending limit)** activo mientras sea free account.
3. **Tags** (`project`, `env`, `owner`) desde el día 1; sin tags no hay desglose.
4. **Pricing Calculator** para estimar cargas nuevas.

## Fuentes de gasto típicas

| Fuente | Cómo evitarla |
|--------|---------------|
| **Egress (salida de datos)** | Solo 15 GB gratis en 12 meses; comprimir y no mover datos entre regiones sin motivo |
| **IPs públicas estáticas** | Cobran aunque no se usen; usar efímeras |
| **Disks (Managed Disks)** | Se factura el disco aunque la VM esté apagada/desasignada |
| **Load Balancer / Application Gateway** | Cobro por hora; en dev, evitar |
| **VM apagada (no desasignada)** | Estado "Stopped" cobra compute; hay que **desasignar (deallocate)** |
| **Premium SSD / almacenamiento caliente** | Elegir LRS estándar; mover datos fríos a Archive |
| **AKS: nodos** | El plano de control es gratis, los nodos no |

## Diagnóstico

- **Cost Management** (análisis por recurso, tag, grupo) y **Cost alerts**.
- **Azure Advisor → Cost**: right-sizing y recursos infrautilizados.
- **Tags view**: quién gasta qué.
- **Reservations / Savings Plans**: solo para carga estable.

## Optimización (cuando se paga)

- **Right-sizing** primero; luego **autoscaling**; reservas solo para lo predecible.
- **App Service / Functions** antes que VM para cargas intermitentes.
- **Blob lifecycle** (hot → cool → archive → delete) para datos que envejecen.
- Apagar (desasignar) o eliminar entornos de dev fuera de horario.

## Errores comunes

| Error | Consecuencia |
|-------|--------------|
| "Apago la VM y ya no pago" | En estado Stopped **sí** cobra compute; hay que desasignar |
| Dejar el límite de gasto quitado | Se factura sin tope |
| Varias B1s en free | Es 750 h en total; la segunda se paga |
| Ignorar los 12 meses | Todo lo que siga corriendo pasa a on-demand |
| Sin tags | Cost Management no puede repartir el gasto |
