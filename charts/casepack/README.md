# CasePack Helm Chart

Umbrella Helm chart that deploys the full CasePack stack — API, SPA, PostgreSQL, Keycloak, and SeaweedFS — in a single command.

## Quick Start

```bash
helm repo add bysamio https://bysamio.github.io/charts/
helm repo update

helm upgrade --install casepack bysamio/casepack \
  --namespace casepack \
  --create-namespace
```

This installs CasePack with all bundled infrastructure using default dev credentials. **Not suitable for production without overrides.**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   CasePack Umbrella Chart                    │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ casepack-api │  │ casepack-spa │  │    postgresql     │  │
│  │  (subchart)  │  │  (subchart)  │  │    (subchart)     │  │
│  └──────┬───────┘  └──────────────┘  └────────┬─────────┘  │
│         │                                      │            │
│         ├──── OIDC auth ──┐                    │            │
│         ├──── JDBC ───────┼────────────────────┘            │
│         │                 │                                 │
│  ┌──────┴───────┐  ┌─────┴──────┐                          │
│  │  seaweedfs   │  │  keycloak  │                          │
│  │  (subchart)  │  │ (subchart) │                          │
│  └──────────────┘  └────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## Subcharts

| Component | Chart | Version | Condition |
|---|---|---|---|
| CasePack API | `casepack-api` | `~0.3.0` | Always enabled |
| CasePack SPA | `casepack-spa` | `~0.1.0` | `casepack-spa.enabled` |
| PostgreSQL | `postgresql` (BySamio) | `~2.0.0` | `postgresql.enabled` |
| Keycloak | `keycloak` (BySamio) | `~1.2.0` | `keycloak.enabled` |
| SeaweedFS | `seaweedfs` (BySamio) | `~1.0.0` | `seaweedfs.enabled` |

## Self-Host License Setup

Self-host deployments require a license JWT. Two options:

### Option A: License Secret (inline)

```yaml
casepack-api:
  config:
    deploymentMode: "self_host"
    installationId: "inst_your-installation-id"
    licenseKeySource: "env"
  secrets:
    licenseTokenFile: "eyJhbGciOiJFZERTQSJ9..."  # Your license JWT
```

The chart creates a `casepack-license` Secret automatically.

### Option B: Existing Secret

```bash
kubectl create secret generic my-license \
  --namespace casepack \
  --from-file=license.jwt=./license.jwt
```

```yaml
casepack-api:
  config:
    deploymentMode: "self_host"
    installationId: "inst_your-installation-id"
    licenseKeySource: "env"
  secrets:
    existingSecret: "my-license"
```

## Production Deployment

Disable bundled infrastructure and point to managed services:

```yaml
# production-values.yaml
postgresql:
  enabled: false

keycloak:
  enabled: false

seaweedfs:
  enabled: false

casepack-api:
  secrets:
    existingSecret: "casepack-api-secrets"
    dbUrl: "jdbc:postgresql://your-db:5432/casepack"
    dbUser: "casepack"
    dbPass: ""
    s3AccessKey: ""
    s3SecretKey: ""
  config:
    deploymentMode: "self_host"
    installationId: "inst_your-installation-id"
    licenseKeySource: "env"
    oidcIssuerUri: "https://auth.example.com/realms/casepack"
    s3Endpoint: "https://s3.amazonaws.com"
    s3Region: "eu-central-1"
    s3PathStyle: "false"
    corsOrigins: "https://casepack.example.com"
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
helm upgrade --install casepack bysamio/casepack \
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
| `casepack-api.config.s3Endpoint` | S3 endpoint | `http://casepack-seaweedfs:8333` |
| `casepack-api.config.corsOrigins` | CORS allowed origins | `http://localhost:5173` |
| `casepack-api.config.deploymentMode` | Deployment mode | `self_host` |
| `casepack-api.config.installationId` | Instance installation ID | `""` |
| `casepack-api.config.licenseKeySource` | License key source | `env` |
| `casepack-api.secrets.existingSecret` | Use pre-created K8s Secret | `""` |
| `casepack-api.secrets.dbUrl` | PostgreSQL JDBC URL | `jdbc:postgresql://casepack-postgresql:5432/casepack` |
| `casepack-api.secrets.dbPass` | Database password | `casepack` |
| `casepack-api.secrets.licenseTokenFile` | License JWT (creates Secret) | `""` |
| `casepack-api.ingress.enabled` | Enable API Ingress | `false` |

### CasePack SPA (`casepack-spa.*`)

| Parameter | Description | Default |
|---|---|---|
| `casepack-spa.enabled` | Deploy bundled SPA | `true` |
| `casepack-spa.replicaCount` | Number of SPA replicas | `1` |
| `casepack-spa.image.repository` | SPA image repository | `ghcr.io/bysamio/casepack-spa` |
| `casepack-spa.config.apiBaseUrl` | API base URL | `http://casepack-casepack-api:80` |
| `casepack-spa.config.oidcAuthority` | OIDC authority URL | `http://casepack-keycloak:8080/realms/casepack` |
| `casepack-spa.ingress.enabled` | Enable SPA Ingress | `false` |

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

### SeaweedFS (`seaweedfs.*`)

| Parameter | Description | Default |
|---|---|---|
| `seaweedfs.enabled` | Deploy bundled SeaweedFS | `true` |
| `seaweedfs.image.repository` | Image repository | `chrislusf/seaweedfs` |
| `seaweedfs.image.tag` | Image tag | `latest` |
| `seaweedfs.s3.port` | S3 gateway port | `8333` |
| `seaweedfs.persistence.size` | PVC size | `10Gi` |

## Keycloak Database Init

When both `postgresql.enabled` and `keycloak.enabled` are `true`, the chart deploys a `post-install` Job that creates the `keycloak` database and user in the bundled PostgreSQL instance.

## Upgrade

```bash
helm upgrade casepack bysamio/casepack \
  --namespace casepack \
  -f your-values.yaml
```

## Uninstall

```bash
helm uninstall casepack --namespace casepack
```

> **Note:** PVCs for PostgreSQL and SeaweedFS are retained after uninstall. Delete them manually if you want a clean slate:
> ```bash
> kubectl delete pvc -l app.kubernetes.io/instance=casepack -n casepack
> ```

## Standalone Charts

| Chart | Helm Repo |
|---|---|
| CasePack API | `bysamio/casepack-api` |
| CasePack SPA | `bysamio/casepack-spa` |
| Keycloak | `bysamio/keycloak` |
| SeaweedFS | `bysamio/seaweedfs` |
| PostgreSQL | `bysamio/postgresql` |

## Support

- [CasePack Deployment Guide](https://github.com/bysamio/casepack)
- [CasePack API Documentation](https://github.com/bysamio/casepack-api)
- [BySamio Charts](https://github.com/bysamio/charts)
