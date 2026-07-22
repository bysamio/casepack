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

The umbrella chart is maintained in [`bysamio/charts`](https://github.com/bysamio/charts/tree/main/casepack) and deploys the full stack as subchart dependencies. Each subchart manages its own Kubernetes resources (Deployments, Services, ConfigMaps, Secrets).

```
helm repo add bysamio https://bysamio.github.io/charts/
helm upgrade --install casepack bysamio/casepack
```

**When to use:** Production Kubernetes clusters, managed Kubernetes (EKS, AKS, GKE), or on-prem K8s.

### 2. Docker Compose

The Docker Compose stack provides a single-command deployment for non-Kubernetes environments.

```
docker compose up -d
```

**When to use:** Single-server deployments, VPS hosting, local development, or environments without Kubernetes.

---

## Service Inventory

| Service | Image | Helm Chart | Version |
|---|---|---|---|
| CasePack API | `ghcr.io/bysamio/casepack-api` | `oci://ghcr.io/bysamio/charts/casepack-api` | `0.3.x` |
| CasePack SPA | `ghcr.io/bysamio/casepack-spa` | `bysamio/casepack-spa` | `0.1.x` |
| Keycloak | `ghcr.io/bysamio/keycloak:26.7.0-optimized` | `oci://ghcr.io/bysamio/charts/keycloak` | `1.2.x` |
| SeaweedFS | `chrislusf/seaweedfs` | `oci://ghcr.io/bysamio/charts/seaweedfs` | `1.0.x` |
| PostgreSQL | `ghcr.io/bysamio/postgresql:17.7-alpine` | `oci://ghcr.io/bysamio/charts/postgresql` | `2.0.x` |

### BySamio Keycloak Image

`ghcr.io/bysamio/keycloak:26.7.0-optimized` is a custom build of Keycloak 26.5.2. The `--import-realm` flag imports `casepack-realm.json` on first start, configuring:

- `casepack` realm
- `casepack-spa` public client (authorization code + PKCE)
- `user` realm role
- `casepack-user-manager` service-account client for API-managed user creation
- `tenant_id` protocol mapper (custom JWT claim)

The self-host realm does not import static human users or the SaaS-only
`casepack_admin` super-admin role. Customer administration is represented by
local CasePack `AppUser.accountRole=CASEPACK_ADMIN`, created through bootstrap
or account administration.

---

## Service Wiring

### Kubernetes (Helm)

Services communicate via Kubernetes DNS. With a release name of `casepack`:

| Service | Kubernetes DNS | Port |
|---|---|---|
| PostgreSQL | `casepack-postgresql-primary` | `5432` |
| Keycloak | `casepack-keycloak` | `80` |
| SeaweedFS S3 | `casepack-seaweedfs-s3` | `8333` |
| CasePack API | `casepack-casepack-api` | `80` |

### Docker Compose

Services communicate via Docker Compose service names:

| Service | Docker DNS | Port |
|---|---|---|
| PostgreSQL | `postgres` | `5432` |
| Keycloak | `keycloak` | `8080` |
| SeaweedFS | `seaweedfs` | `8333` |
| CasePack API | `api` | `8080` |
| CasePack SPA | `spa` | `8080` |

---

## OIDC Configuration

CasePack API is a Spring Boot OAuth2 resource server. It validates JWTs issued by Keycloak.

### JWT Claims

| Claim | Source | Usage |
|---|---|---|
| `sub` | Standard | User ID |
| `tenant_id` | Custom attribute mapper | Tenant isolation |
| `realm_access.roles` | Keycloak realm roles | Basic identity roles; customer admin is local `AppUser.accountRole` |
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

## Object Storage And Presigned URLs

The API uses two S3 endpoint concepts:

| Variable | Purpose |
|---|---|
| `S3_ENDPOINT` | Internal object-storage endpoint used by the API for bucket checks, evidence verification, and export writes |
| `S3_PUBLIC_ENDPOINT` | Optional browser-facing endpoint used only for presigned upload/download URLs |

For local Docker, the default public endpoint is `http://casepack-s3.localhost:8333`, while the API still talks to `http://seaweedfs:8333` internally. For production, publish the S3-compatible gateway at a TLS hostname such as `https://s3.casepack.example.com` and set `S3_PUBLIC_ENDPOINT` to that URL.

If `S3_PUBLIC_ENDPOINT` is blank, the API signs presigned URLs with `S3_ENDPOINT`.

---

## Secrets Management

### Docker Compose

The production `docker-compose.yml` enforces required secrets using the `${VAR:?message}` syntax. No credentials are hardcoded — they must be set in `.env`.

```bash
cp .env.example .env
# Fill in DB_PASS, KC_DB_PASS, KC_ADMIN_PASS
# S3 credentials optional (SeaweedFS dev mode works without them)
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

See the [Deployment Guide](../README.md) for setup instructions.

### Quick Checklist

- [ ] **Strong passwords** — Replace all default credentials
- [ ] **TLS everywhere** — Enable Ingress TLS with cert-manager
- [ ] **CORS lockdown** — Set `corsOrigins` to your exact domain(s)
- [ ] **Resource limits** — Tune CPU/memory requests and limits
- [ ] **Persistence** — Ensure PVCs use durable StorageClasses with backups
- [ ] **Network policies** — Restrict inter-pod communication
- [ ] **Container hardening** — `read_only`, `no-new-privileges` (default in compose)
- [ ] **License activated** — Run `activate.sh` before first start
- [ ] **Monitoring** — Health checks, disk alerts, license expiry notifications

---

## License System

CasePack uses EdDSA-signed JWTs for licensing. Self-host instances require a valid license file to operate.

### Activation Flow

```
Customer ─── purchase ──▶ Licensing Server
   │                         │
   │    activation email     │
   │  (token + portal link)  │
   ◀─────────────────────────┘
   │
   │    ./activate.sh
   │    (token exchange)
   │──────────────────────▶ POST /api/public/activate
   │                         │
   │    license.jwt +        │
   │    installation ID      │
   ◀─────────────────────────┘
   │
   │    docker compose up
   └──▶ API loads license.jwt
```

### Access State Lifecycle

When a license expires, the self-host instance follows a degradation cascade:

| State | Behavior | Trigger |
|---|---|---|
| `ACTIVE` | Full access | Valid, non-expired license |
| `GRACE` | Full access + warning banner | Expired, within 7-day grace period |
| `READ_ONLY_EXPIRED` | Read-only, no new data | Grace period exhausted, within 30 days |
| `EXPORT_ONLY` | Export only, no reads | 30+ days past grace |
| `SUSPENDED` | No access | Administrative suspension |
| `TERMINATED` | No access | Permanent termination |

### Renewal

1. Renew subscription at the licensing portal
2. Download new `license.jwt` or run `./renew-license.sh`
3. Restart the API: `docker compose restart api`

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
