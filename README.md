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
- `curl`, `openssl`, and `python3` (for the activation and renewal scripts)

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
./activate.sh <activation-token>
```

This exchanges your activation token for the instance license and bootstrap files used by the self-host stack.

### 3. Start CasePack

```bash
docker compose up -d
```

| Service | URL |
|---|---|
| CasePack SPA | http://localhost:3000 |
| CasePack API | http://localhost:8080 |
| Keycloak | http://localhost:8081 |

### 4. Sign in as the bootstrap admin

The API bootstraps the local customer, first tenant, and first CasePack admin from the signed activation bundle. Log into the SPA at http://localhost:3000 with the bootstrap admin email associated with your license. When the activation response includes a bootstrap admin email, `activate.sh` prints the one-time temporary password and stores it in `.env` for the first API startup.

After bootstrap, create additional users from CasePack account administration. Creating users directly in Keycloak is not enough for regular users because the API requires explicit local `AppUser` records and tenant memberships.

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

See the [chart documentation](https://github.com/bysamio/charts/tree/main/casepack#readme) for production configuration.

## License Renewal

When your license is about to expire, renew your subscription in the [licensing portal](https://licensing.bysam.io/portal). Then run:

```bash
./renew-license.sh
```

The script uses the refresh token in `activation.json`, validates the returned instance-bound JWT, replaces `license.jwt` atomically, keeps a backup, and restarts the API. For air-gapped/manual renewal, download a license JWT from the portal and run:

```bash
./renew-license.sh --file ./license.jwt
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
| `S3_ENDPOINT` | No | Internal S3 endpoint used by the API (default: bundled SeaweedFS) |
| `S3_PUBLIC_ENDPOINT` | No | Browser-facing S3 endpoint for presigned upload/download URLs |
| `S3_ACCESS_KEY` | No | S3 credentials |
| `S3_SECRET_KEY` | No | S3 credentials |

For production browser uploads, set `S3_PUBLIC_ENDPOINT` to a DNS name users can reach, for example `https://s3.casepack.example.com`. Leave `S3_ENDPOINT` pointed at the internal object-storage service when the API should use private networking.

License-related variables are set automatically by `activate.sh`:

| Variable | Description |
|---|---|
| `CASEPACK_DEPLOYMENT_MODE` | `self_host` (set by activate.sh) |
| `CASEPACK_INSTALLATION_ID` | Unique instance ID (set by activate.sh) |
| `CASEPACK_LICENSE_TOKEN_FILE` | Mounted license path inside the API container |
| `CASEPACK_LICENSE_KEY_SOURCE` | `jwks` or `env` (set by activate.sh) |
| `CASEPACK_LICENSE_JWKS_URL` | Licensing JWKS URL when using remote key verification |
| `CASEPACK_ACTIVATION_FILE` | Mounted activation bundle path inside the API container |
| `CASEPACK_SELF_HOST_BOOTSTRAP_ENABLED` | Enables idempotent first-run customer/tenant/admin bootstrap |
| `CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_EMAIL` | Bootstrap admin email from activation, when available |
| `CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_INITIAL_PASSWORD` | One-time temporary password generated by `activate.sh` |

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

See [casepack chart README](https://github.com/bysamio/charts/tree/main/casepack#readme) for full parameter tables.

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
| Helm Chart Reference | [casepack chart README](https://github.com/bysamio/charts/tree/main/casepack#readme) |
| BySamio Charts | [bysamio/charts](https://github.com/bysamio/charts) |

## License

Proprietary. See [LICENSE](LICENSE) for details.
