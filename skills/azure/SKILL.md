---
name: azure
description: Arquitectura, costes y despliegues en Microsoft Azure (VMs, App Service, Blob) incluido el free account y los servicios always-free. Usar al diseñar, desplegar o revisar infraestructura en Azure: compute, almacenamiento, PaaS o control de costes. NO para AWS ('aws'), Oracle Cloud ('oci') ni solo contenedores ('docker'/'kubernetes').
---

# Azure — Patrón senior

> Arquitectura, identidad y control de costes en Microsoft Azure. Anti-patrones y patrones; no es un tutorial de portal.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Infraestructura en Amazon Web Services | `aws` |
| Infraestructura en Oracle Cloud (OCI) | `oci` |
| Solo contenerizar / orquestar | `docker` / `kubernetes` |
| Pipeline de CI/CD (OIDC hacia Azure) | `github-actions` |

> **Frescura (verificado 2026-10-14):** la **cuenta free** da **USD 200 en los primeros 30 días**, más **cantidades mensuales gratis de 20+ servicios durante 12 meses** (solo clientes nuevos) y **65+ servicios always-free**. Hay que pasar a **pay-as-you-go** dentro de los 30 días (o al agotar el crédito) para seguir recibiendo los servicios gratis. Fuentes: `azure.microsoft.com/en-us/pricing/free-services`, `learn.microsoft.com/azure/cost-management-billing/manage/`.

## Cuenta free y cómo se paga

| Fase | Qué pasa |
|------|----------|
| **0–30 días** | USD 200 de crédito (no se acumula al mes siguiente) |
| **Después** | Hay que **pasar a pay-as-you-go** (quitar el límite de gasto) para no perder los servicios gratis |
| **12 meses** | Siguen los "12-month" (B1s, SQL DB, Blob 5 GB, etc.); si siguen usados, **se factura on-demand** |
| **Always** | 65+ servicios gratis en cantidad mensual mientras exista la cuenta |

- **Una sola cuenta free por cliente**.
- Las **cantidades mensuales gratis no se arrastran**: si usas 2 GB de 5 GB, los 3 restantes se pierden.
- **Límite de gasto (spending limit)**: mantenerlo activo mientras sea free account; es el cortafuegos.
- **Azure for Students**: USD 100 sin tarjeta; alternativa si no quieres tarjeta.

## Decisiones y convenciones

- **Resource Groups + tags** desde el origen (`project`, `env`, `owner`): sin tags no hay desglose de costes en Cost Management.
- **Presupuesto obligatorio el día 1**: `Cost Management → Budgets` con alertas al 50 % y 100 % (Cost Management es always-free).
- **Identidad por Entra ID (ex AAD)**: least privilege, sin cuentas locales ni claves estáticas; **OIDC federado desde CI** en lugar de service principal con secreto.
- **PaaS antes que VM**: si el objetivo es free, `App Service` (hasta 10 apps, siempre gratis) o funciones son más baratos que una VM que corre 24/7.
- **VM burstable (B1s / B2pts / B2ats)**: 750 h/mes cada una; una sola VM en free tier, no varias.
- **IaC por defecto** (Bicep/ARM o Terraform) para reproducibilidad.
- **Región fija y barata** en dev; no multi-región sin motivo.

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| Crear recursos sin comprobar que son free | Facturación inmediata | Verificar en la tabla oficial y la etiqueta del recurso |
| Quedarse en free account tras 30 días | Servicios **deshabilitados** | Pasar a pay-as-you-go antes de que venza el crédito |
| Pasar a PAYG sin budget ni límite | Sorpresa de factura | Budget + alertas + revisar Spending |
| Más de una VM B1s gratis | 750 h = ~1 mes completo por VM | Una VM; escalar con PaaS o containers |
| **Load Balancer Standard** | Cobra por hora (aunque con 750 h gratis, luego cobra) | Para dev, Application Gateway/Basic o sin LB |
| IP pública estática permanente | Cobro continuo | Efímera o adjunta a algo en uso |
| Exponer 22/3389 al mundo | Fuerza bruta | NSG restringido o Bastion/SSH con llave |
| Olvidar el fin de los 12 meses | Empieza a cobrarse por lo que siga corriendo | Recordatorio + revisión antes del vencimiento |

## Patrones

### Stack free (coste 0 mientras dure)

```text
App Service (hasta 10 apps, always free) ──► Azure SQL / Cosmos (12 meses gratis)
        │
        ▼
   Entra External ID (reemplaza a B2C; verificar tramo de MAU gratis) · Blob (5 GB / 12 meses) · API Mgmt (1M llamadas always)
```

> **Identidad (verificado 2026-10-14)**: Azure AD B2C **ya no se vende a clientes nuevos** (fin de venta 2025-05-01); los nuevos proyectos usan **Microsoft Entra External ID**. Verificar el tramo de MAU gratis antes de diseñar sobre B2C. Fuente: `learn.microsoft.com/entra/external-id/external-identities-overview`.

### OIDC desde GitHub Actions (sin secretos)

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

## Checklist

- [ ] Recurso verificado como free (tabla oficial + etiqueta)
- [ ] Budget con alertas al 50 % y 100 %
- [ ] Límite de gasto (spending limit) revisado antes de pasar a PAYG
- [ ] Entra ID least privilege + OIDC en CI (sin secretos de service principal)
- [ ] NSG sin 22/3389 abiertos al mundo; sin IP estática innecesaria
- [ ] Tags de cost allocation aplicados
- [ ] Fecha de fin de los 12 meses anotada y recordada
- [ ] Servicios "always free" identificados de los que son de 12 meses

## Fuentes

- **Servicios gratis**: `https://azure.microsoft.com/en-us/pricing/free-services`
- **Cuenta free / crédito**: `https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account`
- **Evitar cargos en free account**: `https://learn.microsoft.com/azure/cost-management-billing/manage/avoid-charges-free-account`
- **FAQ de la cuenta free**: `https://learn.microsoft.com/azure/cost-management-billing/manage/create-free-services`
- **Identidad externa (B2C → External ID)**: `https://learn.microsoft.com/entra/external-id/external-identities-overview`
