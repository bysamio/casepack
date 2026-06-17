#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# CasePack Self-Host Activation Script
#
# Activates a new CasePack installation by exchanging the one-time
# activation token (from your license email) for an instance-bound
# license JWT.
#
# Usage:
#   ./activate.sh <activation-token>
#   ./activate.sh --token-file activation-token.txt
#   ACTIVATION_TOKEN_FILE=activation-token.txt INSTANCE_LABEL=casepack-prod ./activate.sh
#
# Prerequisites:
#   - curl, openssl, and python3 must be installed
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
for cmd in curl openssl python3; do
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

# ── Read or prompt for activation token ─────────────────────────
ACTIVATION_TOKEN=""
if [[ "${1:-}" == "--token-file" ]]; then
    ACTIVATION_TOKEN_FILE="${2:-}"
elif [[ -n "${1:-}" ]]; then
    ACTIVATION_TOKEN="${1}"
fi

if [[ -z "$ACTIVATION_TOKEN" && -n "${ACTIVATION_TOKEN_FILE:-}" ]]; then
    if [[ ! -f "$ACTIVATION_TOKEN_FILE" ]]; then
        echo -e "${RED}Error: Activation token file not found: ${ACTIVATION_TOKEN_FILE}${NC}"
        exit 1
    fi
    ACTIVATION_TOKEN="$(tr -d '\r\n' < "$ACTIVATION_TOKEN_FILE")"
fi

if [[ -z "$ACTIVATION_TOKEN" ]]; then
    echo -e "${YELLOW}Enter your activation token (from the license email):${NC}"
    read -r -p "> " ACTIVATION_TOKEN
fi

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
INSTANCE_LABEL="${INSTANCE_LABEL:-}"
if [[ -z "$INSTANCE_LABEL" ]]; then
    read -r -p "Instance label [$HOSTNAME_DEFAULT]: " INSTANCE_LABEL
fi
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
        \"label\": \"${INSTANCE_LABEL}\"
    }" 2>&1) || {
    echo -e "${RED}Error: Failed to connect to licensing server at ${LICENSING_API}${NC}"
    exit 1
}

HTTP_BODY=$(printf '%s\n' "$HTTP_RESPONSE" | sed '$d')
HTTP_CODE=$(printf '%s\n' "$HTTP_RESPONSE" | tail -n 1)

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo -e "${RED}Activation failed (HTTP $HTTP_CODE):${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

# ── Extract activation fields from response ──────────────────────
parse_json_field() {
    local field="$1"
    python3 -c 'import json, sys
data = json.load(sys.stdin)
value = data
for part in sys.argv[1].split("."):
    value = value.get(part) if isinstance(value, dict) else None
    if value is None:
        break
print("" if value is None else value)' "$field"
}

INSTALLATION_ID=$(printf '%s' "$HTTP_BODY" | parse_json_field "installationId")
LICENSE_JWT=$(printf '%s' "$HTTP_BODY" | parse_json_field "licenseJwt")
REFRESH_TOKEN=$(printf '%s' "$HTTP_BODY" | parse_json_field "refreshToken")
BOOTSTRAP_ADMIN_EMAIL=$(printf '%s' "$HTTP_BODY" | parse_json_field "bootstrapAdmin.email")
CUSTOMER_NAME=$(printf '%s' "$HTTP_BODY" | parse_json_field "customer.name")
JWKS_URL=$(printf '%s' "$HTTP_BODY" | parse_json_field "jwks.url")

if [[ -z "$LICENSE_JWT" ]]; then
    echo -e "${RED}Error: No license JWT in activation response.${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

if [[ -z "$INSTALLATION_ID" ]]; then
    echo -e "${RED}Error: No installation ID in activation response.${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

# ── Write license file ──────────────────────────────────────────
LICENSE_FILE="${LICENSE_FILE:-license.jwt}"
TMP_LICENSE="${LICENSE_FILE}.tmp"
printf '%s' "$LICENSE_JWT" > "$TMP_LICENSE"
mv "$TMP_LICENSE" "$LICENSE_FILE"
# Bind-mounted files must be readable by the non-root API container user.
chmod 644 "$LICENSE_FILE"
echo -e "${GREEN}License written to ${LICENSE_FILE}${NC}"

# ── Write activation bundle ──────────────────────────────────────
ACTIVATION_FILE="${ACTIVATION_FILE:-activation.json}"
TMP_ACTIVATION="${ACTIVATION_FILE}.tmp"
printf '%s' "$HTTP_BODY" > "$TMP_ACTIVATION"
mv "$TMP_ACTIVATION" "$ACTIVATION_FILE"
# Bind-mounted files must be readable by the non-root API container user.
chmod 644 "$ACTIVATION_FILE"
echo -e "${GREEN}Activation bundle written to ${ACTIVATION_FILE}${NC}"

# ── Update .env with deployment settings ─────────────────────────
update_env_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

get_env_var() {
    local key="$1"
    local line
    line="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n 1 || true)"
    if [[ -z "$line" ]]; then
        return 0
    fi
    printf '%s\n' "${line#*=}" | sed 's/[[:space:]]*#.*$//' | xargs
}

update_env_var "CASEPACK_DEPLOYMENT_MODE" "self_host"
update_env_var "CASEPACK_INSTALLATION_ID" "$INSTALLATION_ID"
update_env_var "CASEPACK_LICENSE_TOKEN_FILE" "/run/secrets/license.jwt"
update_env_var "CASEPACK_ACTIVATION_FILE" "/run/secrets/activation.json"
update_env_var "CASEPACK_SELF_HOST_BOOTSTRAP_ENABLED" "true"
update_env_var "CASEPACK_SELF_HOST_BOOTSTRAP_TENANT_NAME" "${CUSTOMER_NAME:-CasePack Workspace}"
if [[ -n "$BOOTSTRAP_ADMIN_EMAIL" ]]; then
    update_env_var "CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_EMAIL" "$BOOTSTRAP_ADMIN_EMAIL"
fi
BOOTSTRAP_ADMIN_PASSWORD=""
if [[ -n "$BOOTSTRAP_ADMIN_EMAIL" ]]; then
    BOOTSTRAP_ADMIN_PASSWORD="$(get_env_var "CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_INITIAL_PASSWORD")"
    if [[ -z "$BOOTSTRAP_ADMIN_PASSWORD" ]]; then
        BOOTSTRAP_ADMIN_PASSWORD="$(openssl rand -base64 18 | tr '/+' '_-' | tr -d '=')"
        update_env_var "CASEPACK_SELF_HOST_BOOTSTRAP_ADMIN_INITIAL_PASSWORD" "$BOOTSTRAP_ADMIN_PASSWORD"
    fi
fi
if [[ -n "$JWKS_URL" ]]; then
    update_env_var "CASEPACK_LICENSE_KEY_SOURCE" "jwks"
    update_env_var "CASEPACK_LICENSE_JWKS_URL" "$JWKS_URL"
else
    update_env_var "CASEPACK_LICENSE_KEY_SOURCE" "env"
fi

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
echo -e "Activation file:  ${BLUE}${ACTIVATION_FILE}${NC}"
if [[ -n "$REFRESH_TOKEN" ]]; then
    echo -e "Renewal:          ${GREEN}unattended refresh token installed${NC}"
else
    echo -e "Renewal:          ${YELLOW}no refresh token returned; portal renewal fallback required${NC}"
fi
if [[ -n "$BOOTSTRAP_ADMIN_EMAIL" ]]; then
    echo -e "Admin email:      ${BLUE}${BOOTSTRAP_ADMIN_EMAIL}${NC}"
fi
if [[ -n "$BOOTSTRAP_ADMIN_PASSWORD" ]]; then
    echo -e "Temp password:    ${YELLOW}${BOOTSTRAP_ADMIN_PASSWORD}${NC}"
    echo -e "                  Change this after first login."
fi
echo
echo -e "Next steps:"
echo -e "  1. Review your ${BLUE}.env${NC} file"
echo -e "  2. Run: ${YELLOW}docker compose up -d${NC}"
echo
echo -e "${BLUE}Kubernetes / Helm users:${NC}"
echo -e "  Provide self-host runtime values through an API env Secret."
echo -e "  Include CASEPACK_LICENSE_TOKEN, CASEPACK_INSTALLATION_ID,"
echo -e "  CASEPACK_DEPLOYMENT_MODE=self_host, database/S3 credentials, and bootstrap envs,"
echo -e "  then install with:"
echo -e "  ${YELLOW}helm upgrade --install casepack ./charts/casepack \\${NC}"
echo -e "  ${YELLOW}  --set casepack-api.secrets.existingSecret=casepack-api-selfhost${NC}"
echo -e "  See ${BLUE}charts/casepack/README.md${NC} for the exact env Secret shape."
