#!/usr/bin/env bash
# Enrolls the API-owned Connected licensing identity. This wrapper never
# creates, parses, or edits installation keys, state, or credentials.
set -euo pipefail

usage() {
  printf '%s\n' \
    "Usage: ./activate.sh [--code-file PATH]" \
    "The enrollment code is read from a protected file or hidden container prompt." \
    "It is never accepted as a positional command argument."
}

CODE_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --code-file)
      CODE_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Error: enrollment codes are not accepted in argv.\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f .env ]]; then
  printf 'Error: .env is missing. Copy .env.example and configure it first.\n' >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif podman compose version >/dev/null 2>&1; then
  COMPOSE=(podman compose -f docker-compose.yml -f docker-compose.podman.yml)
else
  printf 'Error: Docker Compose or Podman Compose is required.\n' >&2
  exit 1
fi

if [[ -n "$CODE_FILE" ]]; then
  if [[ ! -f "$CODE_FILE" ]]; then
    printf 'Error: enrollment code file does not exist.\n' >&2
    exit 1
  fi
  ABSOLUTE_CODE_FILE="$(cd "$(dirname "$CODE_FILE")" && pwd)/$(basename "$CODE_FILE")"
  "${COMPOSE[@]}" run --rm --no-deps \
    -v "${ABSOLUTE_CODE_FILE}:/run/secrets/enrollment-code:ro" \
    api licensectl enroll --code-file /run/secrets/enrollment-code
else
  "${COMPOSE[@]}" run --rm --no-deps api licensectl enroll
fi

printf '%s\n' \
  "Enrollment complete. The durable identity is in the licensing-state volume." \
  "Next: ${COMPOSE[*]} up -d"
