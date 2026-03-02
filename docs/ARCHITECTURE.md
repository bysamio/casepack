# CasePack — Deployment Architecture

This document covers the deployment architecture for the CasePack platform, including both Helm (Kubernetes) and Docker Compose deployment models.

## Table of Contents

- [Dual Deployment Model](#dual-deployment-model)
- [Service Inventory](#service-inventory)
- [Service Wiring](#service-wiring)
- [OIDC Configuration](#oidc-configuration)
- [Secrets Management](#secrets-management)
- [Production Hardening](#production-hardening)

---

## Dual Deployment Model

CasePack supports two deployment methods:

### 1. Helm Umbrella Chart (Kubernetes)

The umbrella chart at `charts/casepack/` deploys the full stack as subchart dependencies. Each subchart manages its own Kubernetes resources (Deployments, Services, ConfigMaps, Secrets).

```
helm install casepack oci://ghcr.io/bysamio/charts/casepack
```

**When to use:** Production Kubernetes clusters, managed Kubernetes (EKS, AKS, GKE), or on-prem K8s.

### 2. Docker Compose

The Docker Compose stack at `docker/` provides a single-command deployment for non-Kubernetes environments.

```
cd docker/ && docker compose up -d
```

**When to use:** Single-server deployments, VPS hosting, local development, or environments without Kubernetes.

---

## Service Inventory

| Service | Image | Helm Chart | Version |
|---|---|---|---|
| CasePack API | `ghcr.io/bysamio/casepack-api` | `oci://ghcr.io/bysamio/charts/casepack-api` | `0.3.x` |
| CasePack SPA | `ghcr.io/bysamio/casepack-spa` | *(coming soon)* | — |
| Keycloak | `ghcr.io/bysamio/keycloak:26.5.2-optimized` | `oci://ghcr.io/bysamio/charts/keycloak` | `1.2.x` |
| MinIO | `minio/minio` | `oci://ghcr.io/bysamio/charts/minio` | `1.0.x` |
| PostgreSQL | `ghcr.io/bysamio/postgresql:17.7-alpine` | `oci://ghcr.io/bysamio/charts/postgresql` | `2.0.x` |

### BySamio Keycloak Image

`ghcr.io/bysamio/keycloak:26.5.2-optimized` is a custom build of Keycloak 26.5.2. The `--import-realm` flag imports `casepack-realm.json` on first start, configuring:

- `casepack` realm
- `casepack-spa` public client (authorization code + PKCE)
- `casepack_admin` and `casepack_user` realm roles
- `tenant_id` protocol mapper (custom JWT claim)
- Demo users: `demo` (casepack_user), `admin` (casepack_admin)

---

## Service Wiring

### Kubernetes (Helm)

Services communicate via Kubernetes DNS. With a release name of `casepack`:

| Service | Kubernetes DNS | Port |
|---|---|---|
| PostgreSQL | `casepack-postgresql` | `5432` |
| Keycloak | `casepack-keycloak` | `8080` |
| MinIO | `casepack-minio` | `9000` |
| CasePack API | `casepack-casepack-api` | `80` |

### Docker Compose

Services communicate via Docker Compose service names:

| Service | Docker DNS | Port |
|---|---|---|
| PostgreSQL | `postgres` | `5432` |
| Keycloak | `keycloak` | `8080` |
| MinIO | `minio` | `9000` |
| CasePack API | `api` | `8080` |

---

## OIDC Configuration

CasePack API is a Spring Boot OAuth2 resource server. It validates JWTs issued by Keycloak.

### JWT Claims

| Claim | Source | Usage |
|---|---|---|
| `sub` | Standard | User ID |
| `tenant_id` | Custom attribute mapper | Tenant isolation |
| `realm_access.roles` | Keycloak realm roles | Authorization (`casepack_admin`, `casepack_user`) |
| `preferred_username` | Standard | Display name |
| `email` | Standard | User email |

### Split-Issuer Pattern (Docker Compose)

In Docker Compose, the browser and the API reach Keycloak on different hostnames:

- **Browser** → `http://localhost:8081/realms/casepack` (host-mapped port)
- **API (internal)** → `http://keycloak:8080/realms/casepack` (Docker DNS)

The JWT `iss` claim matches the **browser-facing** URL. The API must:

1. Set `OIDC_ISSUER_URI` to the browser-facing URL (`http://localhost:8081/realms/casepack`) so the JWT `iss` claim validation passes.
2. Set `OIDC_JWK_SET_URI` to the Docker-internal URL (`http://keycloak:8080/realms/casepack/protocol/openid-connect/certs`) so the API can fetch signing keys over the Docker network.

```yaml
# docker-compose.yml
api:
  environment:
    OIDC_ISSUER_URI: http://localhost:8081/realms/casepack
    OIDC_JWK_SET_URI: http://keycloak:8080/realms/casepack/protocol/openid-connect/certs
```

### Kubernetes (Helm)

In Kubernetes, this split is typically unnecessary. If Keycloak is exposed via Ingress, the issuer URI should match the external URL. When using only internal DNS without Ingress, both the issuer and JWK set URI can use the same Kubernetes DNS name.

```yaml
casepack-api:
  config:
    oidcIssuerUri: "https://auth.example.com/realms/casepack"
    # oidcJwkSetUri defaults to {issuerUri}/protocol/openid-connect/certs
```

---

## Secrets Management

### Docker Compose

The production `docker-compose.yml` enforces required secrets using the `${VAR:?message}` syntax. No credentials are hardcoded — they must be set in `.env`.

```bash
cp .env.example .env
# Fill in DB_PASS, KC_DB_PASS, KC_ADMIN_PASS, S3_ACCESS_KEY, S3_SECRET_KEY
```

### Helm (Kubernetes)

For quickstart, inline values in `values.yaml` provide default credentials. For production:

1. **Create a Kubernetes Secret** with your credentials
2. **Reference it** via `casepack-api.secrets.existingSecret`
3. **Disable inline secrets** (the existingSecret takes precedence)

```bash
kubectl create secret generic casepack-api-secrets \
  --namespace casepack \
  --from-literal=DB_PASS=your-db-password \
  --from-literal=S3_ACCESS_KEY=your-access-key \
  --from-literal=S3_SECRET_KEY=your-secret-key
```

For GitOps workflows, use Sealed Secrets or external secret operators:

```yaml
casepack-api:
  secrets:
    existingSecret: "casepack-api-secrets"
```

---

## Production Hardening

### Checklist

- [ ] **Disable bundled infra** — Use managed PostgreSQL, Keycloak, and S3
- [ ] **Strong passwords** — Replace all default credentials
- [ ] **TLS everywhere** — Enable Ingress TLS with cert-manager
- [ ] **Disable Swagger** — Set `swaggerPublic: false`
- [ ] **CORS lockdown** — Set `corsOrigins` to your exact domain(s)
- [ ] **Resource limits** — Tune CPU/memory requests and limits
- [ ] **Persistence** — Ensure PVCs use durable StorageClasses with backups
- [ ] **Network policies** — Restrict inter-pod communication
- [ ] **Keycloak production mode** — Set `keycloak.production: true` and configure hostname
- [ ] **License token** — Apply your MSP Pro or Enterprise license
- [ ] **Monitoring** — Set up health checks, metrics, and alerting
- [ ] **Backup strategy** — Regular PostgreSQL and MinIO backups

### PostgreSQL Init (Keycloak Database)

The bundled PostgreSQL creates the `casepack` database via `POSTGRES_DB`. The Keycloak database must be created separately:

- **Docker Compose:** The `init-keycloak-db.sh` script is mounted at `/docker-entrypoint-initdb.d/` and runs on first PostgreSQL init.
- **Helm:** The `init-keycloak-db` Job runs as a `post-install` hook when both `postgresql.enabled` and `keycloak.enabled` are true.

### Ingress Configuration

Example Ingress setup with cert-manager:

```yaml
# Helm values
casepack-api:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - host: api.casepack.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: casepack-api-tls
        hosts:
          - api.casepack.example.com

keycloak:
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: auth.casepack.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: keycloak-tls
        hosts:
          - auth.casepack.example.com
```
