#!/usr/bin/env bash
# Connected mode refreshes automatically every 24 hours with jitter. This
# wrapper requests an immediate proof-of-possession refresh without touching
# the API-owned state volume.
set -euo pipefail

if [[ $# -ne 0 ]]; then
  printf 'Usage: ./renew-license.sh\n' >&2
  exit 2
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif podman compose version >/dev/null 2>&1; then
  COMPOSE=(podman compose -f docker-compose.yml -f docker-compose.podman.yml)
else
  printf 'Error: Docker Compose or Podman Compose is required.\n' >&2
  exit 1
fi

"${COMPOSE[@]}" run --rm --no-deps api licensectl refresh
