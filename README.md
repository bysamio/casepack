# CasePack

Turn incidents into audit-ready evidence packs — fast.

CasePack helps MSPs run consistent incident reporting across customers, collect artifacts, and export a client/auditor-ready evidence pack in minutes. Built for NIS2-style deadlines. Self-host-first.

## Features

- **Incident Reporting** — Structured incident workspace with severity, status, NIS2 flags, and inline search
- **Evidence Collection** — Upload logs, screenshots, IOCs, and emails with full version history and tamper-evident audit trail
- **NIS2 Milestone Tracking** — Automatic early warning, notification, and final report deadline milestones. Extensible to GDPR, DORA, and custom SLAs
- **One-Click Evidence Pack Export** — PDF report, ZIP bundle, manifest, and audit log — ready to hand to clients or auditors
- **PSA Integration** — Webhook intake from ConnectWise, HaloPSA, Autotask — auto-create incidents from PSA tickets
- **Multi-Tenant** — Manage incidents across customer workspaces with tenant-level RBAC
- **Audit Trail** — Every mutation logged with actor, action, entity, and timestamp
- **Self-Host First** — Deploy on Docker or Kubernetes with your own storage and identity provider

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
│  │  SeaweedFS  │                                                 │
│  │ (S3 Storage)│                                                 │
│  └─────────────┘                                                 │
└──────────────────────────────────────────────────────────────────┘
```

## Quick Start (Self-Host)

### Prerequisites

- Docker Engine 24+ with Docker Compose v2
- A CasePack license (purchase at [bysam.io](https://bysam.io))
- `curl` and `openssl` (for the activation script)

### 1. Clone and configure

```bash
git clone https://github.com/bysamio/casepack.git
cd casepack
cp .env.example .env
```

Edit `.env` and set the required passwords:
- `DB_PASS` — PostgreSQL password
- `KC_DB_PASS` — Keycloak database password
- `KC_ADMIN_PASS` — Keycloak admin password

### 2. Activate your license

```bash
./activate.sh
```

This generates an installation ID, exchanges your activation token for a license JWT, and configures the `.env` file.

### 3. Start CasePack

```bash
docker compose up -d
```

| Service | URL |
|---|---|
| CasePack SPA | http://localhost:3000 |
| CasePack API | http://localhost:8080 |
| Keycloak | http://localhost:8081 |

### 4. Create your first user

1. Log into Keycloak at http://localhost:8081 with your admin credentials
2. Switch to the `casepack` realm
3. Create a user and assign the `user` realm role (or `casepack_admin` for platform admin access)
4. Log into the SPA at http://localhost:3000

### Helm (Kubernetes)

Add the BySamio Helm repository:

```bash
helm repo add bysamio https://bysamio.github.io/charts/
helm repo update
```

Deploy the full stack:

```bash
helm upgrade --install casepack bysamio/casepack \
  --namespace casepack \
  --create-namespace \
  --values values.yaml
```

See the [chart documentation](charts/casepack/README.md) for production configuration.

## License Renewal

When your license is about to expire, you'll receive email notifications at 30 and 7 days before expiry.

1. Renew your subscription at the [licensing portal](https://licensing.bysam.io/portal)
2. Run the renewal script:

```bash
./renew-license.sh
```

## Configuration

### Key Environment Variables (Docker Compose)

| Variable | Required | Description |
|---|---|---|
| `DB_PASS` | Yes | PostgreSQL password |
| `KC_DB_PASS` | Yes | Keycloak database password |
| `KC_ADMIN_PASS` | Yes | Keycloak admin password |
| `CASEPACK_VERSION` | No | API image tag (default: `0.3.1`) |
| `CORS_ORIGINS` | No | Allowed CORS origins (default: `http://localhost:3000`) |
| `OIDC_ISSUER_URI` | No | Override for external Keycloak |
| `S3_ACCESS_KEY` | No | S3 credentials (SeaweedFS dev mode doesn't require them) |
| `S3_SECRET_KEY` | No | S3 credentials |

License-related variables are set automatically by `activate.sh`:

| Variable | Description |
|---|---|
| `CASEPACK_DEPLOYMENT_MODE` | `self_host` (set by activate.sh) |
| `CASEPACK_INSTALLATION_ID` | Unique instance ID (set by activate.sh) |
| `CASEPACK_LICENSE_KEY_SOURCE` | `env` (set by activate.sh) |

See [.env.example](.env.example) for the full template.

### Key Helm Values

| Parameter | Description |
|---|---|
| `postgresql.enabled` | Deploy bundled PostgreSQL (`true`) |
| `keycloak.enabled` | Deploy bundled Keycloak (`true`) |
| `seaweedfs.enabled` | Deploy bundled SeaweedFS (`true`) |
| `casepack-api.config.deploymentMode` | `self_host` for self-hosted instances |
| `casepack-api.config.installationId` | Unique installation ID |
| `casepack-api.ingress.enabled` | Enable API Ingress (`false`) |
| `casepack-api.secrets.existingSecret` | Use pre-created K8s Secret |

See [charts/casepack/README.md](charts/casepack/README.md) for full parameter tables.

## Licensing

CasePack uses a JWT-based license system. Self-host deployments require a valid license — without one, the API will not start.

| Feature | Description |
|---|---|
| Incidents & Tenants | Multi-tenant incident tracking |
| Audit Log | Full mutation audit trail |
| Evidence Vault | S3-backed evidence storage |
| Evidence Pack Export | PDF/ZIP compliance export |
| Webhooks | PSA tool integration |
| NIS2 Timelines | Regulatory milestone tracking |

See [bysam.io](https://bysam.io) for licensing plans and pricing.

## Standalone Charts

For advanced deployments where you manage each component independently, all charts are available from the `bysamio` Helm repo:

```bash
helm repo add bysamio https://bysamio.github.io/charts/
```

| Component | Chart Name |
|---|---|
| CasePack API | `bysamio/casepack-api` |
| CasePack SPA | `bysamio/casepack-spa` |
| Keycloak | `bysamio/keycloak` |
| SeaweedFS | `bysamio/seaweedfs` |
| PostgreSQL | `bysamio/postgresql` |

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
