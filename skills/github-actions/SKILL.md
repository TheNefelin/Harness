---
name: github-actions
description: "CI/CD con GitHub Actions. Usar cuando se cree, modifique o revise un workflow o pipeline: jobs, matrix, secrets, cache, artifacts, despliegues o publicación de sitios estáticos (GitHub Pages) en GitHub Actions. NO para diseñar el Dockerfile o la imagen ('docker') ni los manifiestos de clúster ('kubernetes'); Actions solo los ejecuta."
---

# GitHub Actions — Patrón senior

> Pipelines de CI/CD con GitHub Actions. Convenciones, anti-patrones y patrones; no es un tutorial de YAML.

> **Frescura (verificado 2026-10-16):** `uses` citados: `actions/checkout@v7`, `setup-node@v7`, `upload-artifact@v7`, `download-artifact@v8`, CodeQL `@v4` y las de Pages (`configure-pages@v6`, `upload-pages-artifact@v5`, `deploy-pages@v5`). La matrix usa solo Node soportado (**18 y 20 están EOL**; 22 en mantenimiento, 24 LTS). Fuentes: `github.com/actions/*/releases`, `github.com/nodejs/Release`.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Dockerfile, imagen o Compose local | `docker` |
| Manifiestos de Kubernetes, Helm, Kustomize, GitOps | `kubernetes` |

Actions **orquesta el pipeline**; el Dockerfile lo diseña `docker` y los manifiestos los define `kubernetes`.

## Decisiones y convenciones

- **Pinear cada `uses`** a un tag mayor (`@v7`) o, mejor, a un SHA completo: nunca `@master`/`@main`. Un action móvil es un riesgo de cadena de suministro.
- **Permisos mínimos**: `permissions: contents: read` a nivel de workflow y **escalar por job** solo lo necesario (`security-events: write`, etc.). Evitar el `write-all` por defecto.
- **`concurrency` con `cancel-in-progress: true`** para CI en PRs: cancela runs viejos de la misma rama.
- **`timeout-minutes`** por job: evita jobs colgados consumiendo minutos.
- **Cache**: usar el `cache:` nativo de `setup-node`/`setup-python`; para cachés manuales, `key` derivada de `hashFiles('**/*-lock.*')` y `restore-keys`.
- **Artifacts** con `retention-days`; subir reportes de test con `if: always()` para tener evidencia aun si el job falla.
- **`npm ci`**, nunca `npm install`, para builds reproducibles desde el lockfile.
- **Deploy separado** con `needs:` (lint/test/build) y `environment:` (con *required reviewers* en producción para aprobación y auditoría).
- **Sitios estáticos (GitHub Pages)**: publicar con las actions oficiales (`configure-pages` → `upload-pages-artifact` → `deploy-pages`) vía **OIDC** (`pages: write` + `id-token: write`); no empujar a una rama `gh-pages` ni usar un PAT.
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
| Publicar Pages empujando a una rama `gh-pages` | Rama extra y, si usa token, credencial de larga vida | `upload-pages-artifact` + `deploy-pages` con OIDC |

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
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '24'
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm test -- --coverage
      - uses: actions/upload-artifact@v7
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
    - uses: actions/checkout@v7
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
    - uses: actions/checkout@v7
    - uses: actions/download-artifact@v8
      with: { name: build-output, path: dist/ }
    - run: kubectl set image deployment/my-app app=my-app:${{ github.sha }}
    - run: kubectl rollout status deployment/my-app --timeout=300s
```

### Deploy de un sitio estático a GitHub Pages

```yaml
name: Deploy a GitHub Pages
on:
  push: { branches: [main] }
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: '24', cache: 'npm' }
      - run: npm ci
      - run: npm run build            # genera el directorio de salida, p. ej. dist/
      - uses: actions/configure-pages@v6
      - uses: actions/upload-pages-artifact@v5
        with:
          path: dist

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    permissions:
      pages: write
      id-token: write
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v5
```

> Requiere **Settings → Pages → Source: GitHub Actions**. No hay rama `gh-pages`, ni `GITHUB_TOKEN`/PAT: `deploy-pages` usa OIDC. `cancel-in-progress: false` evita cortar un deploy a medias.

### Matrix

```yaml
test:
  strategy:
    fail-fast: false
    matrix:
      node: [22, 24]
      os: [ubuntu-latest, windows-latest]
  runs-on: ${{ matrix.os }}
  steps:
    - uses: actions/setup-node@v7
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
    - uses: actions/checkout@v7
    - uses: github/codeql-action/init@v4
      with: { languages: javascript-typescript }
    - uses: github/codeql-action/analyze@v4
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
- [ ] GitHub Pages con `deploy-pages` + OIDC (no rama `gh-pages` ni PAT)
- [ ] Secrets nunca impresos; `env:` cuando se necesitan
- [ ] PRs de fork sin secrets (`pull_request`, no `pull_request_target`)
- [ ] Services con healthcheck para tests de integración
- [ ] Seguridad: CodeQL / dependencias / secretos / imágenes
