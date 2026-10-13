---
name: kubernetes
description: Guía de orquestación con Kubernetes. Usar cuando se cree, modifique o revise manifiestos o despliegues de Kubernetes: deployment, service, ingress, configmap, secret, Helm, Kustomize o GitOps.
---

# Kubernetes - Skill Completo

> Orquestación de contenedores con Kubernetes.
> Transversal, sin dependencias de proyectos específicos.

---

## Tabla de Contenidos

1. [Kubernetes Basics](#1-kubernetes-basics)
2. [K8s Resources](#2-k8s-resources)
3. [Helm](#3-helm)
4. [Deployment](#4-deployment)
5. [Monitoring](#5-monitoring)

---

## 1. Kubernetes Basics

### 1.1 K8s Architecture

```
┌─────────────────────────────────────────────────────┐
│                  K8s Cluster                         │
│  ┌─────────────┐    ┌─────────────┐               │
│  │   Master    │    │   Master    │               │
│  │  (Control   │    │  (Control   │               │
│  │   Plane)    │    │   Plane)    │               │
│  └──────┬──────┘    └──────┬──────┘               │
│         │                   │                      │
│  ┌──────┴───────────────────┴──────┐               │
│  │         Node Pool               │               │
│  │  ┌────────┐  ┌────────┐       │               │
│  │  │ Worker │  │ Worker │       │               │
│  │  │ Node 1 │  │ Node 2 │       │               │
│  │  └────────┘  └────────┘       │               │
│  └─────────────────────────────────┘               │
└─────────────────────────────────────────────────────┘
```

### 1.2 kubectl Commands

```bash
# Context
kubectl config use-context production
kubectl config current-context

# Pods
kubectl get pods -n namespace
kubectl get pods -o wide
kubectl logs -f pod-name
kubectl exec -it pod-name -- /bin/bash
kubectl describe pod pod-name

# Deployments
kubectl get deployments
kubectl apply -f deployment.yaml
kubectl rollout restart deployment/app
kubectl rollout status deployment/app

# Services
kubectl get svc
kubectl get endpoints
kubectl port-forward svc/app 8080:80

# Debug
kubectl top pod
kubectl events --sort-by='.lastTimestamp'
```

---

## 2. K8s Resources

### 2.1 Pod

```yaml
# pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  containers:
    - name: app
      image: my-app:latest
      ports:
        - containerPort: 3000
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
      resources:
        requests:
          memory: "128Mi"
          cpu: "100m"
        limits:
          memory: "256Mi"
          cpu: "500m"
      livenessProbe:
        httpGet:
          path: /health
          port: 3000
        initialDelaySeconds: 30
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /ready
          port: 3000
        initialDelaySeconds: 5
        periodSeconds: 5
```

### 2.2 Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: app-sa
      containers:
        - name: app
          image: my-app:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: app-config
            - secretRef:
                name: app-secrets
          volumeMounts:
            - name: cache
              mountPath: /app/cache
      volumes:
        - name: cache
          emptyDir: {}
```

### 2.3 Service

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-svc
  namespace: production
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
```

### 2.4 Service Types

| Type | Descripción | Uso |
|------|-------------|-----|
| **ClusterIP** | Solo interno | Microservicios |
| **NodePort** | Expuesto en cada nodo | Desarrollo |
| **LoadBalancer** | Balanceador externo | Cloud production |
| **ExternalName** | DNS CNAME | External services |

### 2.5 Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - api.example.com
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
                port:
                  number: 80
```

### 2.6 ConfigMap & Secrets

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_HOST: "db-service"
  REDIS_HOST: "redis-service"
  LOG_LEVEL: "info"
---
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
stringData:
  DATABASE_PASSWORD: "changeme"
  API_KEY: "secret-key"
```

### 2.7 PVC (Persistent Volume)

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
```

### 2.8 Horizontal Pod Autoscaler

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

### 2.9 RBAC

```yaml
# service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: production
---
# role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]
---
# role-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-role-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: production
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

---

## 3. Helm

### 3.1 Helm Commands

```bash
# Install
helm install my-app ./chart
helm install my-app repo/chart-name
helm upgrade my-app ./chart
helm rollback my-app 1

# Repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Values
helm install my-app ./chart --set image.tag=v1.0
helm install my-app ./chart --values values.yaml
```

### 3.2 Chart Structure

```
my-chart/
├── Chart.yaml
├── values.yaml
├── values-prod.yaml
├── values-staging.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl
│   └── configmap.yaml
└── charts/
```

### 3.3 values.yaml

```yaml
replicaCount: 3

image:
  repository: my-app
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

nodeSelector: {}

tolerations: []

affinity: {}
```

### 3.4 _helpers.tpl

```yaml
{{- define "my-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "my-chart.labels" -}}
app.kubernetes.io/name: {{ include "my-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end }}
```

---

## 4. Deployment

### 4.1 Namespace

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    environment: production
---
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    environment: staging
```

### 4.2 Kustomize Overlay

```yaml
# kustomization.yaml (base)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app: my-app
```

```yaml
# production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base
patches:
  - path: deployment-patch.yaml
images:
  - name: my-app
    newTag: v1.2.0
```

### 4.3 GitOps with ArgoCD

```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: production
  source:
    repoURL: https://github.com/org/repo
    targetRevision: HEAD
    path: k8s/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 5. Monitoring

### 5.1 Prometheus + Grafana

```yaml
# prometheus.yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
spec:
  serviceAccountName: prometheus
  serviceMonitorSelector:
    matchLabels:
      team: backend
  resources:
    requests:
      memory: 1Gi
      cpu: 500m
```

```yaml
# service-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  labels:
    team: backend
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      path: /metrics
```

### 5.2 Logging with Loki

```yaml
# pod with logging
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "3000"
  prometheus.io/path: "/metrics"
```

---

## Checklist

### Kubernetes
- [ ] Resource limits
- [ ] Liveness/Readiness probes
- [ ] RBAC configured
- [ ] Secrets via Vault o external-secrets
- [ ] HPA configured

### Helm
- [ ] Values por ambiente
- [ ] Helpers definidos
- [ ] Version pinning

### CI/CD
- [ ] Image scanning (Trivy)
- [ ] Resource quotas
- [ ] Network policies

---

*Kubernetes Modern Skill*
*Versión: 1.0*
