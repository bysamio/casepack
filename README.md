# CasePack

Turn incidents into audit-ready evidence packs — fast.

CasePack is a multi-tenant incident management, documentation and evidence platform for MSPs. It keeps the complete response record — incident details, timeline events, evidence, NIS2 milestones, reports, and audit history — in one workspace, then turns it into client-, insurer-, regulator-, and auditor-ready outputs. The private self-host preview supports Docker Compose or compatible Podman Compose; Kubernetes remains demand-gated.

## Features

- **Incident Management** — Create, search, filter, track, and resolve incidents with severity and status, affected-user counts, root cause, and lessons learned
- **Incident Timeline** — Build a chronological response record with categorized event, containment, eradication, recovery, and note entries
- **Evidence Vault** — Attach logs, screenshots, IOCs, emails, and other files to incidents in S3-compatible object storage
- **NIS2 Milestone Tracking** — Track early-warning, incident-notification, and final-report deadlines, with overdue visibility
- **Incident Reports** — Preview and generate initial triage, executive summary, final evidence pack, and NIS2 notification reports from structured incident data
- **Evidence Pack Export** — Produce PDF/ZIP deliverables with evidence, manifests, and audit history for clients, insurers, regulators, or auditors
- **PSA Webhook Intake** — Create incidents from ConnectWise, HaloPSA, Autotask, or generic PSA webhook workflows
- **Audit Log** — Keep a chronological record of incident, evidence, export, webhook, and milestone activity
- **Multi-Tenant Workspaces** — Manage multiple customer organizations with tenant isolation and role-based access for owners, members, and viewers
- **Identity and User Administration** — Authenticate through Keycloak/OIDC and manage users and tenant memberships from CasePack
- **Self-Hosted Design-Partner Preview** — Run the supported single-API Docker Compose/Podman profile on customer-operated PostgreSQL and S3-compatible storage

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
│        ├──────────── HTML → PDF ───────────┐                    │
│        │                                   ▼                    │
│        │                             ┌─────────────┐             │
│        │                             │ Gotenberg   │             │
│        │                             │ PDF Render  │             │
│        │                             └─────────────┘             │
│        ▼                                                         │
│  ┌─────────────┐                                                 │
│  │  SeaweedFS  │                                                 │
│  │ (S3 Storage)│                                                 │
│  └─────────────┘                                                 │
└──────────────────────────────────────────────────────────────────┘
```

## Self-Host Preview Publication Gate

The Compose/Podman wrapper, API-owned state volume, and Connected enrollment
scripts are implemented here for engineering verification. Public installation
commands are intentionally withheld until clean install, upgrade, rollback,
restore, state-loss, and licensing-outage canaries pass against a signed
compatibility set.

Accepted design partners receive the pinned operator runbook during onboarding.
It requires Docker Engine 24+ with Compose v2 or a compatible Podman Compose
setup, one short-lived enrollment code for the assigned deployment slot, and
durable encrypted backups. Enrollment reads the code from a protected prompt
or owner-readable file; it is never accepted as a command-line value or stored
in `.env`.

The API image creates and exclusively owns the durable installation ID,
Ed25519 key, state checksum, and current credential in the `licensing-state`
volume. The first customer, workspace, and administrator are bootstrapped only
after that key-bound credential verifies.

### Kubernetes/Helm

The Connected pilot currently supports one API replica in the
Compose/Podman profile. Helm remains demand-gated until a design partner selects
that deployment profile and its state-volume, recovery, upgrade, and rollback
canary passes. Existing charts are not a promise of Connected-pilot support.

## License Renewal

Connected deployments refresh their key-bound credential every 24 hours with
per-deployment jitter. The private, pinned operator runbook includes explicit
refresh and diagnostic procedures.

The API signs a fresh proof with its non-exported deployment key, strictly
verifies the returned EdDSA credential against the offline issuer trust set,
rejects sequence rollback, and atomically updates its protected state. This
preview does not claim air-gapped operation.

## Configuration

### Key Environment Variables (Docker Compose)

| Variable | Required | Description |
|---|---|---|
| `DB_PASS` | Yes | PostgreSQL password |
| `KC_DB_PASS` | Yes | Keycloak database password |
| `KC_ADMIN_PASS` | Yes | Keycloak admin password |
| `CASEPACK_API_VERSION` | No | API image tag (default: `0.33.0`) |
| `CORS_ORIGINS` | No | Allowed CORS origins (default: `http://localhost:3000`) |
| `OIDC_ISSUER_URI` | No | Override for external Keycloak |
| `S3_ENDPOINT` | No | Internal S3 endpoint used by the API (default: bundled SeaweedFS) |
| `S3_PUBLIC_ENDPOINT` | No | Browser-facing S3 endpoint for presigned upload/download URLs |
| `GOTENBERG_URL` | No | Internal Gotenberg URL used by the API for PDF report rendering |
| `S3_ACCESS_KEY` | No | S3 credentials |
| `S3_SECRET_KEY` | No | S3 credentials |

For production browser uploads, set `S3_PUBLIC_ENDPOINT` to a DNS name users can reach, for example `https://s3.casepack.example.com`. Leave `S3_ENDPOINT` pointed at the internal object-storage service when the API should use private networking.

### SMTP

Configure Keycloak SMTP before the first startup when deploying CasePack for multiple users. Keycloak uses it to deliver invitations, password-setup links, and password-reset emails.

Add your SMTP provider settings to `.env`:

```dotenv
KC_SMTP_HOST=smtp.example.com
KC_SMTP_PORT=587
KC_SMTP_FROM=noreply@example.com
KC_SMTP_FROM_DISPLAY_NAME=CasePack
KC_SMTP_AUTH=true
KC_SMTP_USER=your-smtp-username
KC_SMTP_PASSWORD=your-smtp-password
KC_SMTP_STARTTLS=true
KC_SMTP_SSL=false
```

Keep the real SMTP password only in `.env` and do not commit that file to source control.

Port `587` with STARTTLS is the common configuration. For providers that require implicit TLS on port `465`, set `KC_SMTP_PORT=465`, `KC_SMTP_STARTTLS=false`, and `KC_SMTP_SSL=true`. For an unauthenticated private relay, set `KC_SMTP_AUTH=false` and leave the username and password blank. Do not enable STARTTLS and SSL at the same time.

These values are applied when the `casepack` realm is imported on its first startup. For an existing installation, open the Keycloak Admin Console, select the **casepack** realm, go to **Realm settings → Email**, enter the same values, and use **Test connection**. See the [Keycloak email configuration guide](https://www.keycloak.org/docs/latest/server_admin/#configuring-email-for-a-realm) for provider-specific options.

Connected licensing and bootstrap variables are configured before enrollment:

| Variable | Description |
|---|---|
| `CASEPACK_DEPLOYMENT_MODE` | `self_host` (set by activate.sh) |
| `CASEPACK_LICENSE_PUBLIC_KEY` | Base64URL-encoded, pinned offline issuer JWK supplied during design-partner onboarding |
| `LICENSING_API_URL` | Single HTTPS Connected licensing origin |
| `CASEPACK_SELF_HOST_BOOTSTRAP_ENABLED` | Enables idempotent first-run customer/tenant/admin bootstrap |
| `CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_EMAIL` | First local CasePack admin email |
| `CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_INITIAL_PASSWORD` | One-time temporary password; rotate after first login |

See [.env.example](.env.example) for the full template.

### Helm Values (Engineering Reference Only)

The chart has not completed the Connected-pilot canary and is not a supported
customer profile. These values are retained for future engineering work:

| Parameter | Description |
|---|---|
| `postgresql.enabled` | Deploy bundled PostgreSQL (`true`) |
| `keycloak.enabled` | Deploy bundled Keycloak (`true`) |
| `gotenberg.enabled` | Deploy bundled internal Gotenberg PDF renderer (`true`) |
| `seaweedfs.enabled` | Deploy bundled SeaweedFS (`true`) |
| `casepack-api.config.deploymentMode` | `self_host` for self-hosted instances |
| `casepack-api.config.installationId` | Unique installation ID |
| `casepack-api.ingress.enabled` | Enable API Ingress (`false`) |
| `casepack-api.secrets.existingSecret` | Use pre-created K8s Secret |

See [casepack chart README](https://github.com/bysamio/charts/tree/main/casepack#readme) for full parameter tables.

## Licensing

CasePack Connected V1 separates one commercial entitlement from up to two
deployment identities (primary and recovery/test). Credential refreshes are
internal revisions, not additional licenses. A proven-empty deployment without
an enrollment enters `SETUP`; a populated deployment with missing, corrupt,
expired, revoked, or unrestored state enters `RECOVERY_READ_EXPORT`, preserving
authenticated reads and complete export while ordinary writes are blocked.

Connected V1 contacts only the configured licensing origin and sends the
deployment identity, key thumbprint, proof/challenge metadata, product version,
and deployment profile. It does not send incidents, evidence, tenants, users,
IdP configuration, storage configuration, or workflow content. A valid
credential provides up to 30 days of continuity; revocation and cloned-volume
enforcement can therefore lag until that credential expires.

| Feature | Description |
|---|---|
| Incidents & Tenants | Multi-tenant incident tracking |
| Audit Log | Full mutation audit trail |
| Evidence Vault | S3-backed evidence storage |
| Evidence Pack Export | PDF/ZIP compliance export |
| Webhooks | PSA tool integration |
| NIS2 Timelines | Regulatory milestone tracking |
| Incident Timeline | Categorized chronological response record |
| Incident Reports | Template-based report preview and generation |

See [bysam.io](https://bysam.io) for licensing plans and pricing.

## Standalone Charts (Not Part of the Connected Preview)

Charts may exist in the `bysamio` repository, but their presence is not a
support or compatibility promise for Connected licensing. Repository and
installation commands stay unpublished until Helm passes its separate
supportability gate.

| Component | Chart Name |
|---|---|
| CasePack API | `bysamio/casepack-api` |
| CasePack SPA | `bysamio/casepack-spa` |
| Keycloak | `bysamio/keycloak` |
| Gotenberg | `bysamio/gotenberg` |
| SeaweedFS | `seaweedfs/seaweedfs` |
| PostgreSQL | `bysamio/postgresql` |

## Documentation

| Resource | Link |
|---|---|
| Official Documentation | [CasePack Docs](https://docs.casepack.app) |
| Deployment Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Helm Chart Reference | [casepack chart README](https://github.com/bysamio/charts/tree/main/casepack#readme) |
| BySamio Charts | [bysamio/charts](https://github.com/bysamio/charts) |

## License

Proprietary. See [LICENSE](LICENSE) for details.
