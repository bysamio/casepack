# CasePack

Multi-tenant incident evidence management platform for MSPs. Self-host-first. Built for NIS2-style compliance workflows.

CasePack helps Managed Service Providers document, track, and export incident evidence with built-in regulatory timelines — deployable in minutes on Kubernetes or Docker.

## Features

- **Incident Management** — Create, track, and soft-delete incidents with enriched metadata
- **Evidence Chain** — Immutable evidence upload via S3 presigned URLs with server-side verification
- **NIS2 Regulatory Timelines** — Auto-generate 24h/72h/30d milestones for NIS2-reportable incidents. Extensible to GDPR, DORA, and custom SLA timelines
- **Audit Trail** — Every mutation logged with actor, action, entity, and timestamp
- **Evidence Pack Export** — One-click PDF/ZIP export with incident summary, evidence manifest, audit log, and NIS2 timeline section
- **Webhook Intake** — HMAC-SHA256 signed inbound webhooks from PSA tools (ConnectWise, HaloPSA, Autotask)
- **User Management** — Auto-provisioned shadow users with tenant-level RBAC (Owner/Manager/Member/Viewer)
- **Multi-Tenant Security** — JWT-based tenant isolation with Keycloak OIDC, optional per-tenant S3 bucket isolation
- **Rate Limiting** — Per-tenant token-bucket rate limiting on evidence and global request caps

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         CasePack Stack                           │
│                                                                  │
│  ┌────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │  CasePack  │    │   Keycloak   │    │     PostgreSQL       │  │
│  │    SPA     │───▶│   (OIDC)     │    │   (Data Store)       │  │
│  └─────┬──────┘    └──────┬───────┘    └──────────┬───────────┘  │
│        │                  │                       │              │
│        ▼                  │                       │              │
│  ┌─────────────┐          │                       │              │
│  │  CasePack   │◀─── OIDC auth ──────────────────┘              │
│  │    API      │──── JDBC ────────────────────────┘              │
│  └─────┬───────┘                                                 │
│        │                                                         │
│        ▼                                                         │
│  ┌─────────────┐                                                 │
│  │    MinIO    │                                                 │
│  │ (S3 Storage)│                                                 │
│  └─────────────┘                                                 │
└──────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Helm (Kubernetes)

Deploy the full stack with a single command:

```bash
helm install casepack oci://ghcr.io/bysamio/charts/casepack \
  --namespace casepack \
  --create-namespace
```

This deploys CasePack API, PostgreSQL, Keycloak, and MinIO with default dev credentials. See the [chart documentation](charts/casepack/README.md) for production configuration.

### Docker Compose

```bash
cd docker/
cp .env.example .env
# Edit .env with your credentials (required fields are marked)
docker compose up -d
```

| Service | URL |
|---|---|
| CasePack API | http://localhost:8080 |
| Keycloak | http://localhost:8081 |
| MinIO Console | http://localhost:9001 |

For local development with default credentials and Swagger UI enabled:

```bash
cd docker/
docker compose -f docker-compose.dev.yml up -d
```

## Configuration

### Key Environment Variables (Docker Compose)

| Variable | Required | Description |
|---|---|---|
| `DB_PASS` | Yes | PostgreSQL password |
| `KC_DB_PASS` | Yes | Keycloak database password |
| `KC_ADMIN_PASS` | Yes | Keycloak admin password |
| `S3_ACCESS_KEY` | Yes | MinIO root user |
| `S3_SECRET_KEY` | Yes | MinIO root password |
| `CASEPACK_VERSION` | No | API image tag (default: `0.3.1`) |
| `CORS_ORIGINS` | No | Allowed CORS origins |
| `OIDC_ISSUER_URI` | No | Override for external Keycloak |

See [docker/.env.example](docker/.env.example) for the full template.

### Key Helm Values

| Parameter | Description |
|---|---|
| `postgresql.enabled` | Deploy bundled PostgreSQL (`true`) |
| `keycloak.enabled` | Deploy bundled Keycloak (`true`) |
| `minio.enabled` | Deploy bundled MinIO (`true`) |
| `casepack-api.ingress.enabled` | Enable API Ingress (`false`) |
| `casepack-api.secrets.existingSecret` | Use pre-created K8s Secret |

See [charts/casepack/README.md](charts/casepack/README.md) for full parameter tables.

## Licensing

CasePack uses a JWT-based license system. Without a license token, the API runs on the **Starter** plan (free tier).

| Feature | Starter | MSP Pro | MSP Enterprise |
|---|---|---|---|
| Incidents & Tenants | ✓ (1 tenant) | ✓ (25 tenants) | ✓ (unlimited) |
| Audit Log | — | ✓ | ✓ |
| Evidence Vault | — | ✓ | ✓ |
| Evidence Pack Export | — | ✓ | ✓ |
| Webhooks | — | ✓ | ✓ |
| NIS2 Timelines | — | ✓ | ✓ |
| Users | 10 | 50 | Unlimited |
| Self-Host Instances | — | 3 | 25 |

## Standalone Charts

For advanced deployments where you manage each component independently:

| Component | OCI URL | Version |
|---|---|---|
| CasePack API | `oci://ghcr.io/bysamio/charts/casepack-api` | `0.3.x` |
| Keycloak | `oci://ghcr.io/bysamio/charts/keycloak` | `1.2.x` |
| MinIO | `oci://ghcr.io/bysamio/charts/minio` | `1.0.x` |
| PostgreSQL | `oci://ghcr.io/bysamio/charts/postgresql` | `2.0.x` |

## Documentation

| Resource | Link |
|---|---|
| Deployment Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Helm Chart Reference | [charts/casepack/README.md](charts/casepack/README.md) |
| API Development | [bysamio/casepack-api](https://github.com/bysamio/casepack-api) |
| SPA Development | [bysamio/casepack-spa](https://github.com/bysamio/casepack-spa) |
| BySamio Charts | [bysamio/charts](https://github.com/bysamio/charts) |

## License

Proprietary. See [LICENSE](LICENSE) for details.
