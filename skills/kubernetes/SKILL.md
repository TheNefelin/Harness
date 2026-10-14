---
name: kubernetes
description: Orquestación con Kubernetes. Usar cuando se cree, modifique o revise manifiestos o despliegues de Kubernetes: deployment, service, ingress, configmap, secret, Helm, Kustomize o GitOps. NO usar para construir la imagen o correr contenedores locales (eso es la skill 'docker') ni para pipelines de CI/CD (eso es 'github-actions').
---

# Kubernetes — Patrón senior

> Orquestación de contenedores con Kubernetes. Convenciones, anti-patrones y manifiestos clave; no es un tutorial de `kubectl`.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Construir la imagen o correr contenedores locales | `docker` |
| Pipeline de CI/CD (jobs, matrix, secrets, deploy) | `github-actions` |

Kubernetes **orquesta**: la imagen se define en `docker` y el pipeline en `github-actions`.

## Decisiones y convenciones

- **`resources.requests` y `limits` siempre**: sin ellos el scheduler no planifica bien y un pod puede tumbar el nodo. Requests = lo que reserva; limits = techo.
- **Probes**: `readinessProbe` (¿atiende tráfico?) y `livenessProbe` (¿está vivo?) **distintas**. Agregar `startupProbe` si el arranque es lento. Una liveness agresiva = reinicios en loop.
- **Nunca `image: latest`**: pin de `tag` inmutable o `digest` (`@sha256:...`); `imagePullPolicy: IfNotPresent` con tag fijo, `Always` solo si el tag es móvil (no recomendado).
- **RollingUpdate con `maxUnavailable: 0`**: cero downtime; `maxSurge` para capacidad extra durante el rolling.
- **Namespaces por entorno** (dev/staging/prod), no todo en `default`.
- **Config por entorno sin duplicar YAML**: Kustomize (base + overlays) o Helm (chart + `values-<env>.yaml`). Nunca editar manifiestos a mano en prod.
- **Secrets fuera de git**: un `Secret` de K8s es **base64, no cifrado**. Usar External Secrets / Sealed Secrets / Vault; jamás credenciales en el manifiesto commiteado.
- **`securityContext` no-root**: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`.
- **HPA** sobre CPU (y memoria si aplica) en vez de escalar a mano.
- **RBAC least privilege**: un `ServiceAccount` por app con permisos mínimos; no usar `default`.
- **GitOps** (ArgoCD/Flux) para despliegue declarativo; `kubectl apply` manual solo en desarrollo.
- **Alta disponibilidad**: `PodDisruptionBudget`, `topologySpreadConstraints`/anti-affinity, réplicas ≥ 2.

## Tipos de Service

| Tipo | Alcance | Uso típico |
|------|---------|-----------|
| **ClusterIP** | Solo interno al cluster | Microservicios (default) |
| **NodePort** | Expuesto en cada nodo | Desarrollo/acceso puntual |
| **LoadBalancer** | Balanceador externo del cloud | Entrada pública |
| **ExternalName** | CNAME a un DNS externo | Integrar servicios externos |

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| Sin `requests`/`limits` | Scheduler ciego; un pod degrada el nodo | Definir ambos en cada contenedor |
| `image: latest` | Deploys no reproducibles | Tag inmutable o digest |
| Secret commiteado / "cifrado" base64 | Fuga de credenciales | External/Sealed Secrets o Vault |
| Credenciales en `ConfigMap` | Quedan en texto plano y visibles | `Secret` referenciado, gestionado fuera de git |
| Todo en el namespace `default` | Sin aislamiento entre entornos | Un namespace por entorno |
| `privileged: true` / correr como root | Escalada de privilegios | `securityContext` no-root + drop caps |
| Sin probes | Tráfico a pods no listos; sin auto-recuperación | readiness + liveness (y startup) |
| Misma probe para readiness y liveness | Reinicios innecesarios por lentitud puntual | Separar responsabilidades |
| `ServiceAccount` default con permisos | Superficie de ataque | SA por app con RBAC mínimo |
| `kubectl apply` manual a prod | Drift, sin historial ni rollback | GitOps (ArgoCD/Flux) |

## Manifiestos clave

### Deployment (con probes, resources, rolling update y seguridad)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels: { app: my-app }
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels: { app: my-app }
    spec:
      serviceAccountName: app-sa
      securityContext:
        runAsNonRoot: true
      containers:
        - name: app
          image: my-app:1.2.3            # nunca :latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef: { name: app-config }
            - secretRef: { name: app-secrets }
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits: { cpu: "500m", memory: "256Mi" }
          readinessProbe:
            httpGet: { path: /ready, port: 3000 }
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 30
            periodSeconds: 10
```

### Service + Ingress (con TLS)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-svc
  namespace: production
spec:
  type: ClusterIP
  selector: { app: my-app }
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [api.example.com]
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app-svc
                port: { number: 80 }
```

### HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: my-app }
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
```

### RBAC (ServiceAccount + Role + RoleBinding)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: app-sa, namespace: production }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: app-role, namespace: production }
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: app-role-binding, namespace: production }
subjects:
  - { kind: ServiceAccount, name: app-sa, namespace: production }
roleRef: { kind: Role, name: app-role, apiGroup: rbac.authorization.k8s.io }
```

### Kustomize (base + overlay) y Helm (values por entorno)

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml, service.yaml, configmap.yaml]
commonLabels: { app: my-app }
---
# production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [../../base]
images:
  - name: my-app
    newTag: 1.2.3        # pin por entorno, sin editar el base
```

Helm: un chart, `values.yaml` base + `values-<env>.yaml` como override; fijar la versión del chart y no usar `latest` en `image.tag`.

## Checklist

- [ ] `requests` y `limits` en cada contenedor
- [ ] `readinessProbe` y `livenessProbe` (y `startupProbe` si aplica)
- [ ] Imagen con tag inmutable o digest (no `latest`)
- [ ] `RollingUpdate` con `maxUnavailable: 0`
- [ ] `securityContext` no-root (drop caps, `allowPrivilegeEscalation: false`)
- [ ] Un namespace por entorno
- [ ] Secrets gestionados fuera de git (External/Sealed Secrets, Vault)
- [ ] Config por entorno vía Kustomize overlays o Helm values
- [ ] `ServiceAccount` por app con RBAC mínimo
- [ ] HPA configurado
- [ ] Despliegue declarativo (GitOps) en vez de `kubectl apply` manual
- [ ] PDB y anti-affinity/topology spread para HA
