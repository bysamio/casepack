# CasePack MVP Skeleton (React + Spring Boot)

## What’s included
- `../casepack-spa/`: React SPA (Vite) + Keycloak OIDC login + starter routes (tenants → incidents → evidence upload)
- `../casepack-api/`: Spring Boot API + Postgres/Flyway + JWT validation + MinIO/S3 presigned upload endpoints
- `docker-compose.local.yml`: Postgres + MinIO + Keycloak + API
- `../casepack-infra/keycloak/realm-casepack.json`: realm import with a demo user

## Quickstart
1) Start infra + API:
   docker compose up --build

2) Create MinIO bucket: - done automatically on startup
   - Console: http://localhost:9001 (minioadmin / minioadmin)
   - Create bucket: `casepack`

3) Run the web dev server:
   cd ../casepack-spa
   cp .env.example .env
   npm install
   npm run dev

4) Login:
   - http://localhost:4173/login
   - Keycloak: user `demo` / password `demo`

Then:
- Create a tenant
- Create an incident
- Upload evidence (browser PUT directly to MinIO using presigned URL)
