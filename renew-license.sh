#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# CasePack Self-Host License Renewal Script
#
# Downloads the latest license JWT from the licensing portal after
# you have renewed your subscription.
#
# Usage:
#   ./renew-license.sh
#
# Prerequisites:
#   - curl must be installed
#   - .env must contain CASEPACK_INSTALLATION_ID
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

LICENSING_PORTAL="${LICENSING_PORTAL_URL:-https://licensing.bysam.io/portal}"

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   CasePack License Renewal               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo

# ── Check prerequisites ──────────────────────────────────────────
if ! command -v curl &>/dev/null; then
    echo -e "${RED}Error: 'curl' is required but not found.${NC}"
    exit 1
fi

# ── Load .env ────────────────────────────────────────────────────
ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

if [[ -z "${CASEPACK_INSTALLATION_ID:-}" ]]; then
    echo -e "${RED}Error: CASEPACK_INSTALLATION_ID not set.${NC}"
    echo "Run activate.sh first, or set it in your .env file."
    exit 1
fi

LICENSE_FILE="license.jwt"

# ── Back up current license ──────────────────────────────────────
if [[ -f "$LICENSE_FILE" ]]; then
    BACKUP="${LICENSE_FILE}.$(date +%Y%m%d%H%M%S).bak"
    cp "$LICENSE_FILE" "$BACKUP"
    echo -e "Backed up current license to ${BLUE}${BACKUP}${NC}"
fi

echo
echo -e "${YELLOW}Please log in to the licensing portal to download your renewed license:${NC}"
echo -e "  ${BLUE}${LICENSING_PORTAL}${NC}"
echo
echo -e "After downloading, place the ${BLUE}license.jwt${NC} file in this directory."
echo -e "Then restart CasePack: ${YELLOW}docker compose restart api${NC}"
echo

read -r -p "Have you placed the new license.jwt file? [y/N]: " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "Aborted. Run this script again when ready."
    exit 0
fi

# ── Validate license file ────────────────────────────────────────
if [[ ! -f "$LICENSE_FILE" ]]; then
    echo -e "${RED}Error: ${LICENSE_FILE} not found.${NC}"
    exit 1
fi

# Basic JWT format check (3 dot-separated parts)
JWT_PARTS=$(tr '.' '\n' < "$LICENSE_FILE" | wc -l)
if [[ "$JWT_PARTS" -lt 3 ]]; then
    echo -e "${RED}Error: ${LICENSE_FILE} does not look like a valid JWT.${NC}"
    exit 1
fi

chmod 600 "$LICENSE_FILE"

echo
echo -e "${GREEN}License file validated.${NC}"
echo -e "Restarting CasePack API..."
echo

docker compose restart api 2>/dev/null || {
    echo -e "${YELLOW}Could not auto-restart via Docker Compose. Run manually:${NC}"
    echo "  docker compose restart api"
    echo
    echo -e "${BLUE}Kubernetes / Helm users:${NC}"
    echo "  kubectl create secret generic casepack-license \\"
    echo "    --namespace casepack \\"
    echo "    --from-file=license.jwt=./license.jwt \\"
    echo "    --dry-run=client -o yaml | kubectl apply -f -"
    echo "  kubectl rollout restart deployment/casepack-casepack-api -n casepack"
}

echo
echo -e "${GREEN}License renewal complete!${NC}"
