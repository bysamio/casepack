#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# CasePack Self-Host Activation Script
#
# Activates a new CasePack installation by exchanging the one-time
# activation token (from your license email) for an instance-bound
# license JWT.
#
# Usage:
#   ./activate.sh
#
# Prerequisites:
#   - curl and openssl must be installed
#   - The script must be run from the repo root (same directory as .env)
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

LICENSING_API="${LICENSING_API_URL:-https://licensing.bysam.io}"

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   CasePack Self-Host Activation          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo

# ── Check prerequisites ──────────────────────────────────────────
for cmd in curl openssl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: '$cmd' is required but not found.${NC}"
        exit 1
    fi
done

# ── Check .env exists ────────────────────────────────────────────
ENV_FILE="${ENV_FILE:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${YELLOW}Warning: $ENV_FILE not found. Creating from .env.example...${NC}"
    if [[ -f ".env.example" ]]; then
        cp .env.example "$ENV_FILE"
    else
        echo -e "${RED}Error: Neither $ENV_FILE nor .env.example found.${NC}"
        echo "Run this script from the repo root directory."
        exit 1
    fi
fi

# ── Generate installation ID ────────────────────────────────────
INSTALLATION_ID="inst_$(openssl rand -hex 16)"
echo -e "Installation ID: ${GREEN}${INSTALLATION_ID}${NC}"
echo

# ── Prompt for activation token ─────────────────────────────────
echo -e "${YELLOW}Enter your activation token (from the license email):${NC}"
read -r -p "> " ACTIVATION_TOKEN

if [[ -z "$ACTIVATION_TOKEN" ]]; then
    echo -e "${RED}Error: Activation token cannot be empty.${NC}"
    exit 1
fi

if [[ ! "$ACTIVATION_TOKEN" =~ ^act_ ]]; then
    echo -e "${RED}Error: Invalid token format. Token should start with 'act_'.${NC}"
    exit 1
fi

# ── Prompt for instance label ────────────────────────────────────
HOSTNAME_DEFAULT=$(hostname -s 2>/dev/null || echo "casepack-instance")
read -r -p "Instance label [$HOSTNAME_DEFAULT]: " INSTANCE_LABEL
INSTANCE_LABEL="${INSTANCE_LABEL:-$HOSTNAME_DEFAULT}"

echo
echo -e "${BLUE}Activating with licensing server...${NC}"

# ── Call activation API ──────────────────────────────────────────
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${LICENSING_API}/api/public/activate" \
    -H "Content-Type: application/json" \
    -d "{
        \"token\": \"${ACTIVATION_TOKEN}\",
        \"product\": \"casepack\",
        \"installationId\": \"${INSTALLATION_ID}\",
        \"label\": \"${INSTANCE_LABEL}\"
    }" 2>&1) || {
    echo -e "${RED}Error: Failed to connect to licensing server at ${LICENSING_API}${NC}"
    exit 1
}

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo -e "${RED}Activation failed (HTTP $HTTP_CODE):${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

# ── Extract license JWT from response ────────────────────────────
LICENSE_JWT=$(echo "$HTTP_BODY" | grep -o '"licenseJwt":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$LICENSE_JWT" ]]; then
    echo -e "${RED}Error: No license JWT in activation response.${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

# ── Write license file ──────────────────────────────────────────
LICENSE_FILE="license.jwt"
echo -n "$LICENSE_JWT" > "$LICENSE_FILE"
chmod 600 "$LICENSE_FILE"
echo -e "${GREEN}License written to ${LICENSE_FILE}${NC}"

# ── Update .env with deployment settings ─────────────────────────
update_env_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

update_env_var "CASEPACK_DEPLOYMENT_MODE" "self_host"
update_env_var "CASEPACK_INSTALLATION_ID" "$INSTALLATION_ID"
update_env_var "CASEPACK_LICENSE_KEY_SOURCE" "env"

# Clean up sed backup files
rm -f "${ENV_FILE}.bak"

echo -e "${GREEN}Updated ${ENV_FILE} with deployment settings.${NC}"

echo
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Activation Complete!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo
echo -e "Installation ID:  ${BLUE}${INSTALLATION_ID}${NC}"
echo -e "License file:     ${BLUE}${LICENSE_FILE}${NC}"
echo
echo -e "Next steps:"
echo -e "  1. Review your ${BLUE}.env${NC} file"
echo -e "  2. Run: ${YELLOW}docker compose up -d${NC}"
echo
echo -e "${BLUE}Kubernetes / Helm users:${NC}"
echo -e "  Create a license secret and pass it to the chart:"
echo -e "  ${YELLOW}kubectl create secret generic casepack-license \\${NC}"
echo -e "  ${YELLOW}  --namespace casepack \\${NC}"
echo -e "  ${YELLOW}  --from-file=license.jwt=./license.jwt${NC}"
echo -e "  Then install with:"
echo -e "  ${YELLOW}helm install casepack oci://ghcr.io/bysamio/charts/casepack \\${NC}"
echo -e "  ${YELLOW}  --set casepack-api.config.deploymentMode=self_host \\${NC}"
echo -e "  ${YELLOW}  --set casepack-api.config.installationId=${INSTALLATION_ID} \\${NC}"
echo -e "  ${YELLOW}  --set casepack-api.secrets.existingSecret=casepack-license${NC}"
