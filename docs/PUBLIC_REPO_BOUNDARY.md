# Public Repository Boundary

This repository is intended to be the customer-cloneable CasePack self-host wrapper. Treat every committed file as public.

## Belongs Here

- Customer quick starts for Docker Compose and Helm.
- `.env.example` with placeholders and safe defaults.
- Docker Compose and Helm chart wiring.
- Public troubleshooting for install, login, object storage, license activation, and renewal.
- Public architecture diagrams that explain required customer-operated components.
- Security guidance customers need to operate the stack safely.

## Does Not Belong Here

- Real activation tokens, license JWTs, refresh tokens, passwords, or customer data.
- Internal Stripe, licensing-server, or billing reconciliation runbooks.
- Private support procedures, hidden SaaS super-admin operations, or debug playbooks.
- Local workstation paths or private infrastructure details.
- Internal implementation reviews that mention unreleased systems, temporary bugs, or private deployment topology.

## Where Internal Details Should Go

Move internal implementation plans, smoke-test notes, operator runbooks, and private release checklists to a private engineering or operations repository. If an internal note is useful to customers, rewrite it as customer-facing guidance before copying it here.

## Release Checklist Before Making This Repo Public

- Confirm `git status` contains no secret-bearing files such as `.env`, `.env.bak`, `license.jwt`, `activation.json`, or activation-token files.
- Review `docs/` and remove or relocate internal implementation notes.
- Confirm `README.md`, `.env.example`, `docker-compose.yml`, and [casepack chart README](https://github.com/bysamio/charts/tree/main/casepack#readme) agree on ports, images, license activation, and S3 endpoint behavior.
- Confirm images and charts referenced by the quick start are anonymously readable.
- Run `helm lint casepack` in the `bysamio/charts` repo and a clean Docker Compose smoke test.
