---
name: oci
description: "Arquitectura, costes y despliegues en Oracle Cloud Infrastructure (OCI), con foco en Always Free y en no generar cobros. Usar al diseñar o desplegar en Oracle Cloud: instancias Ampere, redes, buckets, backups o control de costes. NO para AWS ('aws') ni Azure ('azure') ni solo contenedores ('docker'/'kubernetes')."
---

# OCI — Patrón senior

> Despliegue en Oracle Cloud Infrastructure con la particularidad de que su **Always Free es generoso pero estricto**: si excedes los límites, los recursos se terminan. Anti-patrones y patrones.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Infraestructura en Amazon Web Services | `aws` |
| Infraestructura en Microsoft Azure | `azure` |
| Solo contenerizar / orquestar | `docker` / `kubernetes` |
| Solo publicar un sitio (no infraestructura) | `github-actions` |

> **Frescura (verificado 2026-10-17):** el **Always Free** de OCI quedó en **2 OCPU + 12 GB RAM** (Ampere A1) y **200 GB de Block Volume**, reducido desde 4 OCPU / 24 GB (cambio efectivo ~2026-06-15; los incumplimientos empezaron a deshabilitarse ~2026-08-18, según reportes de la comunidad/InfoQ, no un aviso oficial). Fuente oficial: `docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm`.

## Always Free (límites duros)

| Recurso | Límite gratuito |
|---------|-----------------|
| **Compute ARM** (`VM.Standard.A1.Flex`) | **2 OCPU + 12 GB RAM** totales (≈1.500 OCPU-h y 9.000 GB-h/mes) |
| **Compute x86** (`VM.Standard.E2.1.Micro`) | 2 instancias (1/8 OCPU, 1 GB c/u) |
| **Block Volume** | **200 GB** totales (boot + datos); 5 backups |
| **Object Storage** | ~20 GB |
| **Egress (salida)** | 10 TB/mes |
| **Load Balancer** | 1 flexible (10 Mbps) |

- Las cifras de **ARM** son el punto donde más gente se equivoca: son **totales por cuenta**, no por instancia. Sumar todas las A1 antes de crear otra.
- Reportes de usuarios indican que cuentas **Pay As You Go** podrían conservar más CPU ARM gratis; **sin confirmación oficial**, verificar antes de depender de ello.

## Reglas para no facturar

1. **Etiqueta "Always Free Eligible"**: si no aparece al crear el recurso, **no lo crees**.
2. **Home region**: los volúmenes gratuitos solo valen en la home region; crear recursos en otra región genera cargo.
3. **Budget el día 1**: `Billing & Cost Management → Budgets` (p. ej. USD 1/mes) con alertas al **50 % y 100 %**.
4. **Reclamo por inactividad**: Oracle puede **reclamar** instancias Always Free si en **7 días seguidos** se cumplen **las tres**: CPU p95 < 20 %, red < 20 % y memoria < 20 % (A1). Se evita con actividad mínima (un cron o un sitio con visitas); la doc no garantiza que una instancia reclamada se recupere.
5. **Exceder los límites de Always Free**: si tienes más recursos Ampere A1 de los que permite la cuenta, Oracle **deshabilita y luego elimina** las instancias tras **30 días** salvo que pases a Pay As You Go.
6. **IPs reservadas sin adjuntar cobran**: solo son gratis mientras estén asignadas a una instancia en uso.
7. **Discos, snapshots y backups**: todo lo que exceda los 200 GB / 5 backups es cargo.

## Decisiones y convenciones

- **ARM A1 (Ampere)** como base por rendimiento/precio; verificar capacidad de la región antes de planificar.
- **Imagen Ubuntu LTS ARM64** y **clave SSH pública** (sin contraseñas).
- **Firewall = Security List / NSG del VCN** (reglas de red reales); el firewall del SO es la segunda capa.
- **Object Storage para respaldos**, con regla de ciclo de vida (Archive) y descargas **fuera** de la VM.
- **Presupuesto y alertas** son parte del despliegue, no un extra.
- **IaC (Terraform/CLI `oci`)** para reproducibilidad; la consola sirve para empezar.

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| VM sin etiqueta "Always Free Eligible" | Facturación inmediata | Comprobar antes de crear |
| Sumar A1 sin mirar el total | Excedes 2 OCPU / 12 GB → **terminan** tus instancias | Mirar el consumo de toda la cuenta |
| `docker compose down -v` | Borra volúmenes (BD y archivos subidos) | No usarlo salvo borrado deliberado |
| Crear LB adicionales al gratuito | Cobro por hora y GB | 1 LB flexible gratis; después, proxy inverso en la misma VM |
| IPs reservadas sin adjuntar | Cobro continuo | Adjuntar o eliminar |
| Exponer la BD al mundo | Fuga de datos | El compose no debe publicar el puerto de la BD |
| Depender de una VM apagada | Oracle la reclama por inactividad | Actividad mínima continua |
| Regiones no home | Volúmenes gratis no aplican | Desplegar en la home region |

## Patrones

### Stack típico Always Free

```text
VM A1 (2 OCPU / 12 GB, Ubuntu ARM64)
└── Docker Compose
    ├── app (contenedor web)
    └── db (contenedor de base de datos, SIN puerto publicado)
Security List: solo 22 (SSH) y el puerto web · IP pública efímera
Bucket Object Storage (respaldos, ~20 GB) · Budget USD 1/mes con alertas
```

### Reglas de red (Security List)

- Abrir **solo** 22 (SSH con llave) y el puerto de la app.
- **Docker es la excepción importante**: los puertos publicados por contenedores **no pasan** por la cadena `INPUT` del host; Docker los enruta por `FORWARD`. Abrirlos en la **Security List**, sin tocar iptables.
- iptables del SO solo aplica a servicios corriendo **directamente** en la VM (regla antes de la que rechaza todo, p. ej. `iptables -I INPUT 6`).

## Checklist

- [ ] Recurso marcado **Always Free Eligible** y en la **home region**
- [ ] Suma total de A1 ≤ 2 OCPU / 12 GB; Block Volume ≤ 200 GB; backups ≤ 5
- [ ] Budget con alertas al 50 % y 100 %
- [ ] SSH solo con llave; fail2ban activo
- [ ] Security List: solo 22 + puerto web; BD sin puerto público
- [ ] IP reservada solo si está adjunta a una instancia en uso
- [ ] Respaldos descargados **fuera** de la VM (probada su restauración)
- [ ] Actividad mínima programada para evitar el reclamo por inactividad

## Fuentes

- **Always Free (oficial)**: `https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm`
- **Free Tier (general)**: `https://www.oracle.com/cloud/free/`
