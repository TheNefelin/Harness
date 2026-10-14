# OCI — dónde vive cada cosa en la consola

> Mapa de navegación (menú ☰ arriba a la izquierda). Útil porque en OCI **las reglas de firewall no están en la VM ni en Compute**: viven dentro del VCN.

## Compute

| Ruta | Qué vive ahí |
|------|----------------|
| Compute → Instances | Instancia: shape (OCPU/RAM), SO, IP pública en uso |
| instancia → *Networking* → Attached VNICs → IPv4 Addresses | IP privada + IP pública (con etiqueta `(Reserved)` si es reservada) |

## Networking

| Ruta | Qué vive ahí |
|------|----------------|
| Networking → Virtual cloud networks (VCN) | La red completa del proyecto |
| VCN → Security Lists → Default Security List | **Las reglas de firewall reales** (ingress 22, puerto web) |
| VCN → Subnets | La subred (regional) |
| Networking → IP management → Reserved public IPs | IPs reservadas (estado *Assigned* = adjuntas a una instancia) |

## Storage

| Ruta | Qué vive ahí |
|------|----------------|
| Object Storage & Archive → Buckets | Buckets y objetos (respaldos) |
| Block Storage & Compute → Block Volumes | Volúmenes de disco |

## Costes y alertas

| Ruta | Qué vive ahí |
|------|----------------|
| Billing & Cost Management → Budgets | Presupuesto mensual con alertas al 50 % y 100 % |
| Billing & Cost Management → Cost Analysis | Verificar que todo sigue en USD 0 |
| Observability & Management → Monitoring → Alarm Definitions | Alarmas (p. ej. espacio del bucket) |
| Developer Services → Notifications → Topics | Correos de alerta |

## Perfil y herramientas

| Elemento | Para qué |
|----------|----------|
| My profile → Token and Keys → Customer Secret Keys | Credenciales para `rclone`/scripts con Object Storage |
| Ícono `>_` (Cloud Shell) | Terminal pre-autenticada con el CLI `oci` |
| Selector de región (arriba a la derecha) | Debe ser la **home region**; si no, las listas se ven vacías |

## Firewall: dos capas (y el gotcha de Docker)

1. **Security List / NSG de la VCN** (consola): el filtro real del tráfico entrante.
2. **Firewall del sistema**: Ubuntu en OCI trae iptables restrictivo en `INPUT`.

> **Gotcha verificado**: los puertos publicados por contenedores Docker (`ports:` en el compose) **no pasan** por la cadena `INPUT` del host; Docker enruta ese tráfico por `FORWARD`. Para exponer un contenedor basta abrir el puerto en la **Security List**; no hay que tocar iptables.

iptables solo aplica a servicios corriendo **directamente** en la VM:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport PUERTO -j ACCEPT
sudo netfilter-persistent save
```

> La posición `INPUT 6` importa: inserta la regla antes de la que rechaza todo el tráfico.

## Recomendaciones de seguridad

- SSH solo con llaves (viene así por defecto); instalar **fail2ban**.
- Cerrar el puerto de la app al mundo si se usa proxy inverso (Caddy/Nginx en la misma VM con certificados automáticos).
- La base de datos **nunca** debe exponerse públicamente: no agregar `ports` a ese servicio en el compose.
- El **Load Balancer flexible** de 0 Mbps es gratuito, pero para un solo sitio basta un proxy inverso local y apuntar el registro DNS `A` a la IP de la VM.
