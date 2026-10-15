---
name: github-actions
description: "CI/CD con GitHub Actions. Usar cuando se cree, modifique o revise un workflow o pipeline: jobs, matrix, secrets, cache, artifacts o despliegues en GitHub Actions. NO usar para diseñar el Dockerfile o la imagen (eso es la skill 'docker') ni los manifiestos de clúster (eso es 'kubernetes'); Actions solo los ejecuta."
---

# GitHub Actions — Patrón senior

> Pipelines de CI/CD con GitHub Actions. Convenciones, anti-patrones y patrones; no es un tutorial de YAML.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Dockerfile, imagen o Compose local | `docker` |
| Manifiestos de Kubernetes, Helm, Kustomize, GitOps | `kubernetes` |

Actions **orquesta el pipeline**; el Dockerfile lo diseña `docker` y los manifiestos los define `kubernetes`.

## Decisiones y convenciones

- **Pinear cada `uses`** a un tag mayor (`@v4`) o, mejor, a un SHA completo: nunca `@master`/`@main`. Un action móvil es un riesgo de cadena de suministro.
- **Permisos mínimos**: `permissions: contents: read` a nivel de workflow y **escalar por job** solo lo necesario (`security-events: write`, etc.). Evitar el `write-all` por defecto.
- **`concurrency` con `cancel-in-progress: true`** para CI en PRs: cancela runs viejos de la misma rama.
- **`timeout-minutes`** por job: evita jobs colgados consumiendo minutos.
- **Cache**: usar el `cache:` nativo de `setup-node`/`setup-python`; para cachés manuales, `key` derivada de `hashFiles('**/*-lock.*')` y `restore-keys`.
- **Artifacts** con `retention-days`; subir reportes de test con `if: always()` para tener evidencia aun si el job falla.
- **`npm ci`**, nunca `npm install`, para builds reproducibles desde el lockfile.
- **Deploy separado** con `needs:` (lint/test/build) y `environment:` (con *required reviewers* en producción para aprobación y auditoría).
- **PRs de fork**: no tienen secrets. Usar `pull_request` (no `pull_request_target` con checkout del código del PR), que da `GITHUB_TOKEN` de solo lectura.
- **Services** para dependencias de integración (postgres/redis) con `--health-cmd` para esperar disponibilidad real.
- **Matrix** con `fail-fast: false` para ver todos los fallos de una corrida.
- **Seguridad integrada**: CodeQL (SAST), revisión de dependencias, escaneo de secretos y de imágenes.
- **No filtrar secrets**: nunca `echo` de un secret; pasarlos por `env:` (GitHub los enmascara en logs).

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| `uses: org/action@master` | Supply chain / builds no reproducibles | Pinear a tag mayor o SHA |
| `echo "::set-output name=x::v"` | Comando **deprecado** | `echo "x=v" >> "$GITHUB_OUTPUT"` |
| `permissions` sin definir (write-all) | Privilegio excesivo del token | `contents: read` + escalar por job |
| `pull_request_target` + checkout del PR | Código no confiable con secrets | Usar `pull_request`; no checkout de código ajeno con secrets |
| `echo ${{ secrets.X }}` | Fuga en logs | Pasar por `env:` (enmascarado) |
| `npm install` en CI | Instala versiones fuera del lock | `npm ci` |
| Sin `timeout-minutes` | Jobs colgados consumen minutos | Definir timeout por job |
| Sin `concurrency` en PRs | Runs redundantes | `concurrency` + `cancel-in-progress: true` |
| `cache` sin `hashFiles` del lock | Caché obsoleta reutilizada | `key` ligada al lockfile |
| Deploy sin `environment` | Sin aprobación ni trazabilidad | `environment:` con reviewers |

## Patrones

### CI (test + lint + build) con cache y artifact

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm test -- --coverage
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage
          path: coverage/
          retention-days: 7
```

### Tests de integración con services (BD real)

```yaml
integration:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env: { POSTGRES_USER: test, POSTGRES_PASSWORD: test, POSTGRES_DB: test }
      ports: ["5432:5432"]
      options: >-
        --health-cmd pg_isready
        --health-interval 10s --health-timeout 5s --health-retries 5
  steps:
    - uses: actions/checkout@v4
    - run: npm ci
    - run: npm run test:integration
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/test
```

### Deploy a producción (gated + environment)

```yaml
deploy-prod:
  needs: [lint, test, build]
  runs-on: ubuntu-latest
  environment:
    name: production
    url: https://example.com
  permissions:
    contents: read
    id-token: write        # OIDC en vez de claves de larga vida
  steps:
    - uses: actions/checkout@v4
    - uses: actions/download-artifact@v4
      with: { name: build-output, path: dist/ }
    - run: kubectl set image deployment/my-app app=my-app:${{ github.sha }}
    - run: kubectl rollout status deployment/my-app --timeout=300s
```

### Matrix

```yaml
test:
  strategy:
    fail-fast: false
    matrix:
      node: [18, 20, 22]
      os: [ubuntu-latest, windows-latest]
  runs-on: ${{ matrix.os }}
  steps:
    - uses: actions/setup-node@v4
      with: { node-version: ${{ matrix.node }} }
    - run: npm test
```

### Seguridad (SAST + dependencias + secretos)

```yaml
security:
  runs-on: ubuntu-latest
  permissions:
    security-events: write
    contents: read
    actions: read
  steps:
    - uses: actions/checkout@v4
    - uses: github/codeql-action/init@v3
      with: { languages: javascript-typescript }
    - uses: github/codeql-action/analyze@v3
    - name: Escaneo de imagen con Trivy
      uses: aquasecurity/trivy-action@0.28.0     # versión fijada, no @master
      with:
        image-ref: my-app:${{ github.sha }}
        severity: 'HIGH,CRITICAL'
        format: 'sarif'
        output: 'trivy.sarif'
```

> Preferir **OIDC** (`id-token: write`) para desplegar en cloud: elimina claves estáticas de larga vida en secrets.

## Checklist

- [ ] Todas las `uses` pineadas (tag mayor o SHA; nunca `@master`/`@main`)
- [ ] `permissions` mínimos, escalados por job
- [ ] `concurrency` con `cancel-in-progress` en CI
- [ ] `timeout-minutes` en cada job
- [ ] Cache ligada al lockfile (`hashFiles`)
- [ ] `npm ci` (no `npm install`)
- [ ] Artifacts con `retention-days`; reportes con `if: always()`
- [ ] Deploy con `needs` y `environment` (reviewers en prod)
- [ ] Secrets nunca impresos; `env:` cuando se necesitan
- [ ] PRs de fork sin secrets (`pull_request`, no `pull_request_target`)
- [ ] Services con healthcheck para tests de integración
- [ ] Seguridad: CodeQL / dependencias / secretos / imágenes
