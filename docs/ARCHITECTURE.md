# CasePack — Deployment Architecture

This document covers the current CasePack self-host design-partner preview.
Docker Compose/compatible Podman Compose with one API replica is the supported
Connected profile. Existing Helm artifacts are retained for engineering work
but are not a customer-support promise until their state, recovery, upgrade,
and rollback canary passes.

## Table of Contents

- [Dual Deployment Model](#dual-deployment-model)
- [Service Inventory](#service-inventory)
- [Service Wiring](#service-wiring)
- [OIDC Configuration](#oidc-configuration)
- [Secrets Management](#secrets-management)
- [Production Hardening](#production-hardening)

---

## Deployment Profiles

CasePack has two deployment implementations, but only one current preview
profile:

### 1. Docker Compose — Current Preview

The Docker Compose stack is the deployment reference for non-Kubernetes
environments. Installation, enrollment, and recovery commands remain in the
private design-partner runbook until the restore/upgrade canary and release
approval are complete.

**When to use:** Private design-partner preview on a single customer-operated
host. One API replica is enforced by support scope.

### 2. Helm Umbrella Chart — Demand-Gated

The umbrella chart remains in
[`bysamio/charts`](https://github.com/bysamio/charts/tree/main/casepack), but
Connected enrollment, mutable-state PVC ownership, restore reconciliation, and
rollback have not completed a partner canary. Do not offer it as supported.

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

Environment-file preparation and secret-generation steps remain in the private
design-partner runbook until the deployment canary and security review pass.

### Helm (Kubernetes)

Helm is demand-gated and is not part of the Connected preview. Inline sample
credentials are development-only. A future supported profile must use
externally managed Kubernetes Secrets and pass enrollment, state ownership,
backup/restore, upgrade, rollback, and multi-replica tests before its operator
commands are published.

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
- [ ] **Deployment enrolled** — Follow the pinned private runbook before first
      start and keep the `licensing-state` volume durable
- [ ] **Monitoring** — Health checks, disk alerts, license expiry notifications

---

## License System

CasePack Connected V1 separates one commercial entitlement from up to two
key-bound deployment identities. The API image owns local licensing state and
verifies EdDSA credentials against a pinned offline issuer trust set.

### Activation Flow

```
Cleared payment ──▶ entitlement family + active period
                              │
Portal admin ─────▶ one-time slot-bound enrollment code
                              │
API licensectl ───▶ challenge + Ed25519 proof
                              │
Licensing service ▶ installation + credential revision
                              │
API state volume ◀─ strictly verified key-bound credential
```

### Access State Lifecycle

Connected local-state failure follows a data-custody floor:

| State | Behavior | Trigger |
|---|---|---|
| `SETUP` | Enrollment/diagnostics only | Database proven empty and no verified credential |
| `ACTIVE` | Full access | Valid local Connected credential |
| `RECOVERY_READ_EXPORT` | Authenticated reads and permitted exports; ordinary writes paused | Customer data exists or emptiness is uncertain and state is missing, corrupt, restored, expired, or untrusted |

### Renewal

The API refreshes about every 24 hours with jitter. The pinned private runbook
provides the immediate-refresh procedure through the same API image command mode.
Refresh changes only the internal credential revision/head; it never creates a
second entitlement, installation, or customer-visible license.

The local state directory is `/var/lib/casepack/licensing` in the protected
`licensing-state` volume. Back it up with PostgreSQL, object storage, and
identity data. Redeploys must reuse it. A declared restore remains in
`RECOVERY_READ_EXPORT` until a successful server reconciliation confirms the
current installation and sequence.

Credentials provide up to 30 days of continuity. This minimizes dependence on
CasePack availability but delays guaranteed revocation and makes simultaneous
copies of a complete software-key volume impossible to distinguish reliably.
Connected V1 is not air-gapped and is not described as tamper-proof.

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
