# CasePack Helm Chart

Umbrella Helm chart that deploys the full CasePack stack — API, PostgreSQL, Keycloak, and MinIO — in a single command.

## Quick Start

```bash
helm install casepack oci://ghcr.io/bysamio/charts/casepack \
  --namespace casepack \
  --create-namespace
```

This installs CasePack with all bundled infrastructure (PostgreSQL, Keycloak, MinIO) using default dev credentials. **Not suitable for production without overrides.**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   CasePack Umbrella Chart                    │
│                                                             │
│  ┌──────────────┐   ┌────────────┐   ┌──────────────────┐  │
│  │ casepack-api │   │  keycloak  │   │    postgresql     │  │
│  │  (subchart)  │   │ (subchart) │   │    (subchart)     │  │
│  └──────┬───────┘   └──────┬─────┘   └────────┬─────────┘  │
│         │                  │                   │            │
│         ├──── OIDC auth ───┘                   │            │
│         ├──── JDBC ────────────────────────────┘            │
│         │                                                   │
│  ┌──────┴───────┐                                           │
│  │    minio     │                                           │
│  │  (subchart)  │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

## Subcharts

| Component | Chart | Version | Condition |
|---|---|---|---|
| CasePack API | `casepack-api` | `~0.3.0` | Always enabled |
| PostgreSQL | `postgresql` (Bitnami) | `~16.4.0` | `postgresql.enabled` |
| Keycloak | `keycloak` (BySamio) | `~1.2.0` | `keycloak.enabled` |
| MinIO | `minio` (BySamio) | `~1.0.0` | `minio.enabled` |

## Production Deployment

For production, disable the bundled infrastructure and point to your own managed services:

```yaml
# production-values.yaml
postgresql:
  enabled: false

keycloak:
  enabled: false

minio:
  enabled: false

casepack-api:
  secrets:
    existingSecret: "casepack-api-secrets"       # Pre-created K8s Secret
    dbUrl: "jdbc:postgresql://your-db:5432/casepack"
    dbUser: "casepack"
    dbPass: ""                                    # Loaded from existingSecret
    s3AccessKey: ""                               # Loaded from existingSecret
    s3SecretKey: ""                               # Loaded from existingSecret
  config:
    oidcIssuerUri: "https://auth.example.com/realms/casepack"
    s3Endpoint: "https://s3.amazonaws.com"
    s3Region: "eu-central-1"
    s3PathStyle: "false"
    corsOrigins: "https://casepack.example.com"
    swaggerPublic: "false"
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
```

```bash
helm install casepack oci://ghcr.io/bysamio/charts/casepack \
  --namespace casepack \
  --create-namespace \
  -f production-values.yaml
```

## Parameters

### Global

| Parameter | Description | Default |
|---|---|---|
| `global.domain` | Base domain for subcharts | `casepack.example.com` |
| `global.storageClass` | StorageClass for all PVCs | `""` (cluster default) |

### CasePack API (`casepack-api.*`)

| Parameter | Description | Default |
|---|---|---|
| `casepack-api.replicaCount` | Number of API replicas | `1` |
| `casepack-api.image.repository` | API image repository | `ghcr.io/bysamio/casepack-api` |
| `casepack-api.image.tag` | API image tag | `""` (chart appVersion) |
| `casepack-api.config.oidcIssuerUri` | OIDC issuer URI | `http://casepack-keycloak:8080/realms/casepack` |
| `casepack-api.config.s3Endpoint` | S3/MinIO endpoint | `http://casepack-minio:9000` |
| `casepack-api.config.corsOrigins` | CORS allowed origins | `http://localhost:5173` |
| `casepack-api.config.swaggerPublic` | Enable public Swagger UI | `true` |
| `casepack-api.secrets.existingSecret` | Use pre-created K8s Secret | `""` |
| `casepack-api.secrets.dbUrl` | PostgreSQL JDBC URL | `jdbc:postgresql://casepack-postgresql:5432/casepack` |
| `casepack-api.secrets.dbUser` | Database user | `casepack` |
| `casepack-api.secrets.dbPass` | Database password | `casepack` |
| `casepack-api.secrets.s3AccessKey` | S3 access key | `minioadmin` |
| `casepack-api.secrets.s3SecretKey` | S3 secret key | `minioadmin` |
| `casepack-api.ingress.enabled` | Enable API Ingress | `false` |

### PostgreSQL (`postgresql.*`)

| Parameter | Description | Default |
|---|---|---|
| `postgresql.enabled` | Deploy bundled PostgreSQL | `true` |
| `postgresql.auth.database` | Database name | `casepack` |
| `postgresql.auth.username` | Database user | `casepack` |
| `postgresql.auth.password` | Database password | `casepack` |
| `postgresql.auth.postgresPassword` | Superuser password | `postgres` |
| `postgresql.primary.persistence.size` | PVC size | `10Gi` |

### Keycloak (`keycloak.*`)

| Parameter | Description | Default |
|---|---|---|
| `keycloak.enabled` | Deploy bundled Keycloak | `true` |
| `keycloak.auth.adminUser` | Admin username | `admin` |
| `keycloak.auth.adminPassword` | Admin password | `admin` |
| `keycloak.database.host` | Database host | `casepack-postgresql` |
| `keycloak.database.database` | Database name | `keycloak` |
| `keycloak.database.user` | Database user | `keycloak` |
| `keycloak.database.password` | Database password | `keycloak` |
| `keycloak.ingress.enabled` | Enable Keycloak Ingress | `false` |

### MinIO (`minio.*`)

| Parameter | Description | Default |
|---|---|---|
| `minio.enabled` | Deploy bundled MinIO | `true` |
| `minio.auth.rootUser` | Root user | `minioadmin` |
| `minio.auth.rootPassword` | Root password | `minioadmin` |
| `minio.persistence.size` | PVC size | `10Gi` |
| `minio.console.enabled` | Enable MinIO Console | `true` |

## Keycloak Database Init

When both `postgresql.enabled` and `keycloak.enabled` are `true`, the chart deploys a `post-install` Job that creates the `keycloak` database and user in the bundled PostgreSQL instance. This is required because Bitnami PostgreSQL only creates a single database via `auth.database`.

## Upgrade

```bash
helm upgrade casepack oci://ghcr.io/bysamio/charts/casepack \
  --namespace casepack \
  -f your-values.yaml
```

## Uninstall

```bash
helm uninstall casepack --namespace casepack
```

> **Note:** PVCs for PostgreSQL and MinIO are retained after uninstall. Delete them manually if you want a clean slate:
> ```bash
> kubectl delete pvc -l app.kubernetes.io/instance=casepack -n casepack
> ```

## Standalone Charts

For advanced deployments where you manage each component independently:

| Chart | OCI URL |
|---|---|
| CasePack API | `oci://ghcr.io/bysamio/charts/casepack-api` |
| Keycloak | `oci://ghcr.io/bysamio/charts/keycloak` |
| MinIO | `oci://ghcr.io/bysamio/charts/minio` |
| PostgreSQL | `oci://registry-1.docker.io/bitnamicharts/postgresql` |

## Support

- [CasePack Deployment Guide](https://github.com/bysamio/casepack)
- [CasePack API Documentation](https://github.com/bysamio/casepack-api)
- [BySamio Charts](https://github.com/bysamio/charts)
