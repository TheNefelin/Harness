---
name: docker
description: Contenedorización con Docker y Docker Compose. Usar al crear, modificar o revisar un Dockerfile, .dockerignore, docker-compose.yml/compose.yaml, una imagen o un contenedor: build, run, volúmenes, redes, entornos locales multi-servicio o multi-stage builds. NO para orquestación en clúster ('kubernetes') ni pipelines de CI/CD ('github-actions').
---

# Docker + Docker Compose — Patrón senior

> Contenedorización y entornos locales multi-servicio. Decisiones opinadas, anti-patrones y patrones; no es un tutorial de comandos.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Orquestación en clúster (deploy, escala, ingress, Helm) | `kubernetes` |
| Pipeline de CI/CD (jobs, matrix, secrets, deploy) | `github-actions` |

Docker **construye y corre** contenedores; Kubernetes los **orquesta** y Actions los **ejecuta** en el pipeline.

> **Frescura:** usar **Docker Compose v2** (`docker compose`); el binario `docker-compose` v1 está descontinuado. Para .NET, **.NET 8 (LTS) termina soporte el 2026-11-10** y **.NET 9 (STS) el 2026-05-12**: en proyectos nuevos usa **.NET 10 (LTS)**.

## Decisiones y convenciones

- **Multi-stage siempre**: una etapa de build y una etapa final mínima (runtime). Reduce tamaño de imagen y superficie de ataque.
- **Imagen base con tag fijo**: `alpine`/`slim`/`distroless` y versión explícita (p. ej. `python:3.12-slim`, `node:20-alpine`, `mcr.microsoft.com/dotnet/aspnet:10.0`). Nunca `latest` ni tags móviles.
- **Usuario no-root**: crear usuario del sistema y `USER` antes de `CMD`.
- **Cache de capas**: copiar primero el manifiesto de dependencias (`package*.json`, `pyproject.toml` + lock, `*.csproj`) e instalar; recién después `COPY . .`.
- **`.dockerignore` obligatorio**: `node_modules`, `.git`, `bin/`, `obj/`, `__pycache__`, `.env`, tests, coverage.
- **Exec form**: `CMD ["node", "dist/main.js"]` (JSON) en vez de shell form; el shell form no propaga señales ni maneja bien el PID 1.
- **`EXPOSE` es documentación**: no publica el puerto; el mapeo real es `-p` en `run` o `ports` en Compose.
- **Healthcheck** en la imagen o el Compose, para que el orquestador sepa cuándo el servicio está listo.
- **Compose**: `depends_on` con `condition: service_healthy` (no solo `service_started`), volúmenes con nombre para datos persistentes y `restart: unless-stopped`.

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| `FROM node:latest` | Build no reproducible | Tag fijo (alpine/slim) |
| `COPY . .` antes de instalar | Rompe la caché; rebuilds lentos | Copiar manifiesto → instalar → copiar el resto |
| Secretos en `ENV`/`ARG` | Quedan en el historial (`docker history`) | Secretos en runtime (entorno del orquestador o archivos montados) |
| `npm ci --only=production` | Flag obsoleto en npm moderno | `npm ci --omit=dev` |
| Correr como root | Escalada de privilegios | Crear usuario del sistema y `USER` |
| Sin `.dockerignore` | Contexto enorme; puede filtrar secretos | Excluir `node_modules`, `.git`, `.env` |
| `depends_on` sin condición | El servicio arranca antes de que la BD esté lista | `condition: service_healthy` + healthcheck |
| `docker system prune -af` a ciegas | **No** borra volúmenes (falta `--volumes`) ni imágenes en uso; sí elimina contenedores parados, redes e imágenes sin usar | Podar de forma selectiva (`--volumes` solo si sabes qué se borra) |

## Patrones

### Multi-stage (Node)

```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nodejs
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
USER nodejs
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

### Multi-stage (Python/FastAPI)

```dockerfile
FROM python:3.12-slim AS deps
WORKDIR /app
RUN pip install --no-cache-dir poetry
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false && poetry install --only main --no-interaction

FROM python:3.12-slim AS runner
WORKDIR /app
RUN groupadd -r appuser && useradd -r -g appuser appuser
# Copiar site-packages Y los ejecutables (si no, uvicorn falta en la imagen final).
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY . .
USER appuser
EXPOSE 8000
# python -m uvicorn no depende del entrypoint de /usr/local/bin.
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Multi-stage (.NET)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["MyApp.csproj", "./"]
RUN dotnet restore MyApp.csproj
COPY . .
RUN dotnet publish MyApp.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
# Las imágenes .NET 8+ traen un usuario no-root integrado ("app").
USER app
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

### Compose (esencial)

> **Solo para desarrollo local.** Este ejemplo lleva `user:pass` en `environment` a propósito para levantar rápido; **no** lo copies a producción: usa secretos del orquestador y variables fuera del repo.

```yaml
services:
  api:
    build: .
    ports: ["8000:8000"]
    environment:
      DATABASE_URL: postgresql://user:pass@db:5432/app
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: app
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d app"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

## Checklist

- [ ] Multi-stage con etapa final mínima (alpine/slim/distroless)
- [ ] Imagen base con tag fijo (no `latest`)
- [ ] Usuario no-root (`USER`)
- [ ] `.dockerignore` presente y correcto
- [ ] Cache: manifiesto antes que el código
- [ ] `CMD`/`ENTRYPOINT` en exec form
- [ ] Healthcheck definido
- [ ] Sin secretos en `ENV`/`ARG` ni en la imagen
- [ ] Compose: `depends_on` con `condition: service_healthy`
