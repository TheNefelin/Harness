---
name: docker
description: Guía de contenedorización con Docker y Docker Compose. Usar cuando se cree, modifique o revise un Dockerfile, .dockerignore, docker-compose.yml/compose.yaml, una imagen o un contenedor: build, run, volúmenes, redes, entornos locales multi-servicio o multi-stage builds.
---

# Docker + Docker Compose - Skill Completo

> Contenedorización y entornos locales multi-servicio con Docker y Compose.
> Transversal, sin dependencias de proyectos específicos.

---

## Tabla de Contenidos

1. [Docker Fundamentals](#1-docker-fundamentals)
2. [Docker Compose](#2-docker-compose)
3. [Dockerfile Best Practices](#3-dockerfile-best-practices)
4. [Checklist](#4-checklist)

---

## 1. Docker Fundamentals

### 1.1 Comandos Esenciales

```bash
# Build
docker build -t my-app:latest .
docker build -t my-app:latest --build-arg ENV=production .

# Run
docker run -d -p 8080:80 --name my-app my-app:latest
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=secret postgres:16

# Inspect
docker ps
docker logs -f my-app
docker exec -it my-app sh
docker inspect my-app

# Cleanup
docker system prune -af
docker rmi $(docker images -q)
```

### 1.2 Networks

```bash
# Create network
docker network create my-network

# Run with network
docker run -d --network my-network --name api my-api:latest

# Connect containers
docker network connect my-network container2
```

### 1.3 Volumes

```bash
# Named volume
docker volume create my-data
docker run -v my-data:/app/data my-app:latest

# Bind mount (development)
docker run -v $(pwd):/app my-app:latest

# Read-only mount
docker run -v /data:/app/data:ro my-app:latest
```

---

## 2. Docker Compose

### 2.1 Compose V2

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/app
      - REDIS_URL=redis://redis:6379
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - backend
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: app
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d app"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - backend

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
    networks:
      - backend

networks:
  backend:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
```

### 2.2 Compose Commands

```bash
# Up
docker compose up -d
docker compose up -d --build

# Logs
docker compose logs -f
docker compose logs -f api

# Down
docker compose down
docker compose down -v  # Remove volumes

# Scale
docker compose up -d --scale api=3
```

---

## 3. Dockerfile Best Practices

### 3.1 Multi-stage Build (Node/NPM)

```dockerfile
# Stage 1: Dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Builder
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3: Runner
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# Create non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

USER nodejs
EXPOSE 3000

CMD ["node", "dist/main.js"]
```

### 3.2 Multi-stage Build (Python/FastAPI)

```dockerfile
# Stage 1: Dependencies
FROM python:3.12-slim AS dependencies
WORKDIR /app
RUN pip install --no-cache-dir poetry
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false \
    && poetry install --no-dev --no-interaction

# Stage 2: Builder
FROM python:3.12-slim AS builder
WORKDIR /app
COPY --from=dependencies /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY . .

# Stage 3: Runner
FROM python:3.12-slim AS runner
WORKDIR /app
RUN groupadd -r appuser && useradd -r -g appuser appuser
COPY --from=builder /app .
USER appuser
EXPOSE 8000
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 3.3 Multi-stage Build (.NET)

```dockerfile
# Stage 1: Restore
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS restore
WORKDIR /src
COPY ["MyApp.csproj", "./"]
RUN dotnet restore MyApp.csproj

# Stage 2: Build
FROM restore AS build
WORKDIR /src
COPY . .
RUN dotnet build MyApp.csproj -c Release -o /app/build

# Stage 3: Publish
FROM build AS publish
WORKDIR /src
RUN dotnet publish MyApp.csproj -c Release -o /app/publish

# Stage 4: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

### 3.4 Best Practices Summary

| Práctica | ✅ Hacer | ❌ Evitar |
|----------|---------|----------|
| Base image | alpine/slim | latest |
| Layers | Multiple RUN agrupados | RUN separado por comando |
| Caching | Copy package.json primero | Copy todo antes |
| Usuario | Non-root | Root |
| Secrets | Build args, no env | ENV con secrets |
| Multi-stage | Sí | Single stage grande |

---

## 4. Checklist

- [ ] Multi-stage build
- [ ] Non-root user
- [ ] Alpine images
- [ ] .dockerignore
- [ ] Healthcheck

---

*Docker Modern Skill*
*Versión: 1.0*
