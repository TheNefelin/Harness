# Azure Free — detalle por servicio

> Cantidades **verificadas 2026-10-14**; son volátiles. Contrastar con `https://azure.microsoft.com/en-us/pricing/free-services` antes de desplegar. La fuente oficial prevalece.

## Crédito y reglas

- **USD 200** durante **30 días** (no se arrastra al mes siguiente).
- **20+ servicios** con cantidad mensual gratis durante **12 meses** (solo clientes nuevos).
- **65+ servicios always-free** (mientras exista la cuenta).
- **Una cuenta free por cliente**; hay que pasar a **pay-as-you-go** en 30 días o al agotar el crédito.
- Las cantidades **no se acumulan** entre meses.

## 12 meses (cantidad mensual)

| Servicio | Cantidad |
|----------|----------|
| **VMs Linux y Windows** | 750 h de `B1s`, `B2pts v2` (ARM) y `B2ats v2` (AMD) |
| **Blob Storage** | 5 GB LRS (hot) + 20.000 lecturas + 10.000 escrituras |
| **Managed Disks** | 2 discos P6 (64 GB) |
| **Files** | 100 GB |
| **Archive Storage** | 10 GB LRS |
| **Azure SQL Database** | 250 GB, S0 (10 DTU) |
| **Azure SQL Managed Instance** | 720 vCore-horas |
| **Cosmos DB** | 400 RU/s + 25 GB |
| **MySQL / PostgreSQL Flexible** | `B1MS`, 750 h, 32 GB |
| **Load Balancer (Standard)** | 750 h + 15 GB |
| **VPN Gateway** | 750 h (`VpnGw1`), 100 conexiones |
| **Bandwidth (salida)** | 15 GB |
| **Container Registry** | 1 registro Standard, 100 GB |
| **Key Vault** | 10.000 transacciones |
| **Service Bus** | 750 h + 13 M de operaciones |
| **Azure Cache for Redis** | `C0`, 250 MB |
| **Translator** | 2 M de caracteres |
| **App Configuration** | 1.000 requests/día |

## Always free (extracto)

| Servicio | Cantidad |
|----------|----------|
| **App Service** | Hasta 10 apps web, móviles o de API, 1 GB, 1 h/día (F1) |
| **Azure Kubernetes Service (AKS)** | Gestión del clúster gratis (se pagan los nodos) |
| **API Management** | Consumo: 1 M de llamadas |
| **Entra ID B2C** | 50.000 MAU |
| **Azure Functions** | 1 M de ejecuciones + 400.000 GB-s |
| **Service Fabric** | Clúster gratis |
| **Azure Migrate / Update Manager / Arc** | Gratis |
| **Security Center** | Tier gratis (postura y recomendaciones) |
| **Cost Management** | Gratis |
| **Private Link / Azure Resource Manager** | Gratis |
| **Container Storage** | < 5 TiB |
| **Web PubSub** | 20.000 mensajes/día |
| **Cloud Shell** | 5 GB (durante 12 meses) |

> En **AKS/App Service** el servicio en sí es gratis, pero el **compute subyacente** (nodos, horas) puede pagarse si sales del tier free.

## Cómo seguir el consumo

| Vía | Qué da |
|-----|--------|
| `Cost Management` | Coste real, previsto y por tag (always free) |
| `Cost Management → Budgets` | Alertas al 50 % y 100 % |
| Página de **servicios gratis** | Uso restante de cada servicio gratis |
| `Azure Advisor` | Recomendaciones de coste y right-sizing |

## Getchas

- Al terminar los 30 días sin pasar a PAYG, los **servicios se deshabilitan** (no facturan, pero dejan de funcionar).
- Que un servicio sea "12-month" **no** significa que siga gratis después: pasa a on-demand si sigue corriendo.
- B1s usa créditos de ráfaga; en free el **750 h/mes** es una sola VM a tiempo completo.
- Los 15 GB de salida **no se acumulan** y se agotan rápido con cargas grandes.
