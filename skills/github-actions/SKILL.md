---
name: github-actions
description: Guía completa de CI/CD con GitHub Actions. Usar cuando se cree, modifique o revise un workflow o pipeline: jobs, matrix, secrets, cache, artifacts o despliegues en GitHub Actions.
---

# GitHub Actions CI/CD - Skill Completo

> Guía completa para pipelines automatizados con GitHub Actions.
> Transversal, sin dependencias de proyectos específicos.

---

## Tabla de Contenidos

1. [Fundamentos](#1-fundamentos)
2. [Workflow Basics](#2-workflow-basics)
3. [Actions](#3-actions)
4. [Testing](#4-testing)
5. [Build & Deploy](#5-build--deploy)
6. [Security](#6-security)
7. [Advanced](#7-advanced)
8. [Matrix & Concurrency](#8-matrix--concurrency)

---

## 1. Fundamentos

### 1.1 Estructura de GitHub Actions

```
.github/
└── workflows/
    ├── ci.yml           # CI: test, lint, build
    ├── codeql.yml       # Security scanning
    ├── deploy-prod.yml  # Deploy to production
    └── release.yml      # Release automation
```

### 1.2 Conceptos Clave

| Concepto | Descripción |
|----------|-------------|
| **Workflow** | Proceso automatizado completo |
| **Job** | Grupo de steps que ejecutan en el mismo runner |
| **Step** | Acción individual o comando |
| **Action** | Comando reutilizable |
| **Runner** | Máquina que ejecuta el workflow |
| **Artifact** | Archivos generados por el build |

### 1.3 Tipos de Runners

```yaml
# GitHub-hosted runners
runs-on: ubuntu-latest      # Linux (Ubuntu)
runs-on: windows-latest      # Windows
runs-on: macos-latest        # macOS

# Self-hosted runners
runs-on: self-hosted         # Tu propio servidor
runs-on: [self-hosted, linux]  # Con labels
```

---

## 2. Workflow Basics

### 2.1 CI Workflow

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  NODE_VERSION: '20'
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'
          cache-dependency-path: package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
```

### 2.2 Filter Paths

```yaml
on:
  push:
    branches: [main]
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '**.txt'
  pull_request:
    paths:
      - 'src/**'
      - 'package.json'
      - 'package-lock.json'
```

### 2.3 Multiple Triggers

```yaml
on:
  push:
    branches:
      - main
      - 'releases/**'
  pull_request:
    types: [opened, synchronize, reopened]
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to deploy'
        required: true
        default: 'latest'
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
```

---

## 3. Actions

### 3.1 Official Actions

```yaml
# Checkout
uses: actions/checkout@v4

# Node.js
uses: actions/setup-node@v4
with:
  node-version: 20
  cache: 'npm'

# Python
uses: actions/setup-python@v5
with:
  python-version: '3.12'
  cache: 'pip'

# Docker
uses: docker/setup-buildx-action@v3

# AWS
uses: aws-actions/configure-aws-credentials@v4

# Azure
uses: azure/login@v2
```

### 3.2 Docker Build & Push

```yaml
build-and-push:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - uses: docker/setup-buildx-action@v3

    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: |
          ghcr.io/${{ github.repository }}:${{ github.sha }}
          ghcr.io/${{ github.repository }}:latest
        cache-from: type=gha
        cache-to: type=gha,mode=max
        labels: |
          org.opencontainers.image.source=${{ github.repository }}
          org.opencontainers.image.version=${{ github.ref_name }}
```

### 3.3 Custom Actions

```yaml
# action.yml
name: 'My Custom Action'
description: 'Does something useful'
inputs:
  my-input:
    description: 'Input description'
    required: true
    default: 'default-value'
outputs:
  my-output:
    description: 'Output description'
runs:
  using: composite
  steps:
    - run: echo "::set-output name=my-output::value"
      shell: bash
```

---

## 4. Testing

### 4.1 Unit Tests

```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: 20
        cache: 'npm'

    - name: Install dependencies
      run: npm ci

    - name: Run unit tests
      run: npm test -- --coverage

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v4
      with:
        token: ${{ secrets.CODECOV_TOKEN }}
        files: ./coverage/lcov.info
        fail_ci_if_error: true

    - name: Upload test results
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: test-results
        path: coverage/
        retention-days: 30
```

### 4.2 Integration Tests

```yaml
integration-tests:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
        POSTGRES_DB: test
      ports:
        - 5432:5432
      options: >-
        --health-cmd pg_isready
        --health-interval 10s
        --health-timeout 5s
        --health-retries 5

    redis:
      image: redis:7-alpine
      ports:
        - 6379:6379
      options: >-
        --health-cmd "redis-cli ping"
        --health-interval 10s
        --health-timeout 5s

  steps:
    - uses: actions/checkout@v4

    - name: Run integration tests
      run: npm run test:integration
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/test
        REDIS_URL: redis://localhost:6379
```

### 4.3 E2E Tests

```yaml
e2e-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Start application
      run: docker compose up -d

    - name: Wait for app
      run: sleep 10

    - name: Run Cypress tests
      uses: cypress-io/github-action@v6
      with:
        start: npm run start:ci
        wait-on: 'http://localhost:3000'
        wait-on-timeout: 120
        record: true
        parallel: true
      env:
        CYPRESS_RECORD_KEY: ${{ secrets.CYPRESS_RECORD_KEY }}
```

### 4.4 Testing Matrix

```yaml
test:
  strategy:
    fail-fast: false
    matrix:
      node-version: [18, 20, 22]
      operating-system: [ubuntu-latest, windows-latest]
  runs-on: ${{ matrix.operating-system }}
  steps:
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ matrix.node-version }}

    - run: npm test
```

---

## 5. Build & Deploy

### 5.1 Build Stage

```yaml
build:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: 20

    - name: Install dependencies
      run: npm ci

    - name: Lint
      run: npm run lint

    - name: Build
      run: npm run build

    - name: Upload artifact
      uses: actions/upload-artifact@v4
      with:
        name: build-output
        path: dist/
        retention-days: 7
```

### 5.2 Deploy to Staging

```yaml
deploy-staging:
  needs: build
  runs-on: ubuntu-latest
  environment:
    name: staging
    url: https://staging.example.com

  steps:
    - uses: actions/checkout@v4

    - name: Download artifact
      uses: actions/download-artifact@v4
      with:
        name: build-output
        path: dist/

    - name: Deploy to staging
      run: |
        # Deploy using your method (kubectl, terraform, etc.)
        echo "Deploying to staging..."
```

### 5.3 Deploy to Production

```yaml
deploy-prod:
  needs: [build, test]
  runs-on: ubuntu-latest
  environment:
    name: production
    url: https://example.com

  steps:
    - uses: actions/checkout@v4

    - name: Download artifact
      uses: actions/download-artifact@v4
      with:
        name: build-output
        path: dist/

    - name: Configure kubectl
      uses: azure/k8s-set-context@v4
      with:
        kubeconfig: ${{ secrets.KUBECONFIG }}

    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/my-app app=${{ github.repository }}:${{ github.sha }}
        kubectl rollout status deployment/my-app --timeout=300s
```

---

## 6. Security

### 6.1 CodeQL

```yaml
codeql:
  runs-on: ubuntu-latest
  permissions:
    security-events: write
    contents: read
    actions: read

  steps:
    - uses: actions/checkout@v4

    - name: Initialize CodeQL
      uses: github/codeql-action/init@v3
      with:
        languages: javascript, typescript, python

    - name: Build
      run: npm run build

    - name: Run CodeQL analysis
      uses: github/codeql-action/analyze@v3
      with:
        category: "/language:javascript,typescript"
        upload: true
```

### 6.2 Dependency Scanning (Trivy)

```yaml
security-scan:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy results to GitHub
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: 'trivy-results.sarif'
```

### 6.3 Secret Scanning

```yaml
secrets-scan:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Scan for secrets
      uses: trufflesecurity/trufflehog@main
      with:
        path: ./
        base: ${{ github.event.repository.default_branch }}
        extra_args: --json > trufflehog-results.json

    - name: Upload secrets found
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: trufflehog-results
        path: trufflehog-results.json
```

### 6.4 Supply Chain Security

```yaml
supply-chain:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Verify dependencies
      run: |
        npm audit --audit-level=high
        npm audit --fix

    - name: Check for vulnerabilities in images
      uses: aquasecurity/trivy-action@master
      with:
        image: ${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}
        vuln-type: 'os,library'
        severity: 'HIGH,CRITICAL'

    - name: Pin dependencies
      run: npm dedupe
```

---

## 7. Advanced

### 7.1 Caching

```yaml
cache:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: 20
        cache: 'npm'

    # Or manual cache
    - name: Cache node modules
      uses: actions/cache@v4
      with:
        path: ~/.npm
        key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
        restore-keys: |
          ${{ runner.os }}-npm-

    - name: Cache Docker layers
      uses: actions/cache@v4
      with:
        path: /tmp/.buildx-cache
        key: ${{ runner.os }}-buildx-${{ github.sha }}
        restore-keys: |
          ${{ runner.os }}-buildx-
```

### 7.2 Environment Variables

```yaml
env:
  NODE_ENV: production

jobs:
  build:
    env:
      CUSTOM_VAR: 'value'
    steps:
      - run: echo ${{ env.CUSTOM_VAR }}
```

### 7.3 Concurrency

```yaml
name: CI

on: push

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    # Runs on all branches except main
    if: github.ref != 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Running tests..."

  deploy:
    # Only runs on main
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying..."
```

### 7.4 Artifacts

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "test" > artifact.txt

      - uses: actions/upload-artifact@v4
        with:
          name: my-artifact
          path: artifact.txt
          retention-days: 30

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: my-artifact
```

---

## 8. Matrix & Concurrency

### 8.1 Matrix Strategy

```yaml
test:
  strategy:
    fail-fast: false
    matrix:
      include:
        - node-version: 18
          os: ubuntu-latest
        - node-version: 20
          os: ubuntu-latest
        - node-version: 22
          os: windows-latest
        - node-version: 22
          os: macos-latest

  runs-on: ${{ matrix.os }}
  steps:
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ matrix.node-version }}
    - run: npm test
```

### 8.2 Multiple Jobs Parallel

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test

  build:
    runs-on: ubuntu-latest
    steps:
      - run: npm run build

  deploy:
    needs: [lint, test, build]
    runs-on: ubuntu-latest
    steps:
      - run: npm run deploy
```

---

## Checklist

### Basics
- [ ] Workflow en `.github/workflows/`
- [ ] Checkout action
- [ ] Cache configurado
- [ ] Artifact upload/download

### Testing
- [ ] Tests unitarios
- [ ] Coverage upload
- [ ] Integration tests con servicios
- [ ] E2E tests

### Security
- [ ] CodeQL configurado
- [ ] Dependency scanning
- [ ] Secret scanning
- [ ] Images scanning

### Deployment
- [ ] Environments configurados
- [ ] Approval required para prod
- [ ] Rollback strategy
- [ ] Concurrency control

---

*GitHub Actions CI/CD Modern Skill*
*Versión: 1.0*