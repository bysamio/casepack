#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# CasePack Self-Host License Renewal Script
#
# Refreshes the instance-bound license JWT using the activation bundle
# written by activate.sh. This is safe for cron/systemd/Kubernetes jobs:
# the new JWT is checked before it replaces the active license.
#
# Usage:
#   ./renew-license.sh
#   ./renew-license.sh --file ./license.jwt   # air-gapped/manual fallback
#   ./renew-license.sh --no-restart
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

LICENSING_API="${LICENSING_API_URL:-https://licensing.bysam.io}"
ENV_FILE="${ENV_FILE:-.env}"
LICENSE_FILE="${LICENSE_FILE:-license.jwt}"
ACTIVATION_FILE="${ACTIVATION_FILE:-activation.json}"
MANUAL_LICENSE_FILE=""
RESTART_API=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage:
  ./renew-license.sh [--no-restart]
  ./renew-license.sh --file ./license.jwt [--no-restart]

Environment:
  LICENSING_API_URL      Licensing API base URL (default: https://licensing.bysam.io)
  ENV_FILE               Environment file to load (default: .env)
  LICENSE_FILE           License file to replace (default: license.jwt)
  ACTIVATION_FILE        Activation bundle from activate.sh (default: activation.json)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            MANUAL_LICENSE_FILE="${2:-}"
            shift 2
            ;;
        --no-restart)
            RESTART_API=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   CasePack License Renewal               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo

for cmd in curl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}Error: '$cmd' is required but not found.${NC}"
        exit 1
    fi
done

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

if [[ -z "${CASEPACK_INSTALLATION_ID:-}" ]]; then
    echo -e "${RED}Error: CASEPACK_INSTALLATION_ID is not set.${NC}"
    echo "Run ./activate.sh first, or set CASEPACK_INSTALLATION_ID in ${ENV_FILE}."
    exit 1
fi

json_field() {
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

validate_license() {
    local file="$1"
    python3 - "$file" "${CASEPACK_INSTALLATION_ID}" <<'PY'
import base64
import json
import sys

path, expected_inst = sys.argv[1], sys.argv[2]
token = open(path, encoding="utf-8").read().strip()
parts = token.split(".")
if len(parts) != 3:
    raise SystemExit("license is not a JWT")

payload = parts[1] + "=" * (-len(parts[1]) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload.encode()))
inst = claims.get("inst")
product = claims.get("product")
delivery_mode = claims.get("delivery_mode")

if inst != expected_inst:
    raise SystemExit(f"license is bound to {inst!r}, expected {expected_inst!r}")
if product != "casepack":
    raise SystemExit(f"license product is {product!r}, expected 'casepack'")
if delivery_mode != "self_host":
    raise SystemExit(f"license delivery_mode is {delivery_mode!r}, expected 'self_host'")
PY
}

install_license() {
    local source_file="$1"

    validate_license "$source_file"

    if [[ -f "$LICENSE_FILE" ]]; then
        local backup="${LICENSE_FILE}.$(date +%Y%m%d%H%M%S).bak"
        cp "$LICENSE_FILE" "$backup"
        chmod 600 "$backup"
        echo -e "Backed up current license to ${BLUE}${backup}${NC}"
    fi

    local tmp="${LICENSE_FILE}.tmp"
    cp "$source_file" "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$LICENSE_FILE"
    echo -e "${GREEN}Installed renewed license at ${LICENSE_FILE}${NC}"
}

restart_api() {
    if [[ "$RESTART_API" != "true" ]]; then
        echo -e "${YELLOW}Skipping API restart (--no-restart).${NC}"
        return
    fi

    echo -e "${BLUE}Restarting CasePack API...${NC}"
    if docker compose restart api >/dev/null 2>&1; then
        echo -e "${GREEN}API restarted with Docker Compose.${NC}"
        return
    fi
    if podman compose restart api >/dev/null 2>&1; then
        echo -e "${GREEN}API restarted with Podman Compose.${NC}"
        return
    fi

    echo -e "${YELLOW}Could not auto-restart a Compose API service.${NC}"
    echo "Run one of:"
    echo "  docker compose restart api"
    echo "  podman compose restart api"
    echo
    echo "Kubernetes:"
    echo "  kubectl create secret generic casepack-license \\"
    echo "    --namespace casepack \\"
    echo "    --from-file=license.jwt=./license.jwt \\"
    echo "    --dry-run=client -o yaml | kubectl apply -f -"
    echo "  kubectl rollout restart deployment/casepack-casepack-api -n casepack"
}

if [[ -n "$MANUAL_LICENSE_FILE" ]]; then
    if [[ ! -f "$MANUAL_LICENSE_FILE" ]]; then
        echo -e "${RED}Manual license file not found: ${MANUAL_LICENSE_FILE}${NC}"
        exit 1
    fi
    install_license "$MANUAL_LICENSE_FILE"
    restart_api
    echo -e "${GREEN}Manual license renewal complete.${NC}"
    exit 0
fi

if [[ ! -f "$ACTIVATION_FILE" ]]; then
    echo -e "${RED}Activation bundle not found: ${ACTIVATION_FILE}${NC}"
    echo "Run ./activate.sh first, or use ./renew-license.sh --file ./license.jwt."
    exit 1
fi

REFRESH_TOKEN=$(json_field "refreshToken" < "$ACTIVATION_FILE")
if [[ -z "$REFRESH_TOKEN" ]]; then
    echo -e "${RED}No refresh token found in ${ACTIVATION_FILE}.${NC}"
    echo "Use the portal download fallback:"
    echo "  ./renew-license.sh --file ./license.jwt"
    exit 1
fi

echo -e "${BLUE}Requesting renewed license from licensing server...${NC}"
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${LICENSING_API}/api/public/instances/${CASEPACK_INSTALLATION_ID}/license/refresh" \
    -H "Content-Type: application/json" \
    -d "{
        \"product\": \"casepack\",
        \"refreshToken\": \"${REFRESH_TOKEN}\"
    }" 2>&1) || {
    echo -e "${RED}Error: failed to connect to licensing server at ${LICENSING_API}${NC}"
    exit 1
}

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo -e "${RED}License refresh failed (HTTP $HTTP_CODE):${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

NEW_LICENSE=$(printf '%s' "$HTTP_BODY" | json_field "licenseJwt")
if [[ -z "$NEW_LICENSE" ]]; then
    echo -e "${RED}Refresh response did not include licenseJwt.${NC}"
    echo "$HTTP_BODY"
    exit 1
fi

TMP_REFRESHED="${LICENSE_FILE}.refreshed"
printf '%s' "$NEW_LICENSE" > "$TMP_REFRESHED"
chmod 600 "$TMP_REFRESHED"

install_license "$TMP_REFRESHED"
rm -f "$TMP_REFRESHED"

ROTATED_REFRESH_TOKEN=$(printf '%s' "$HTTP_BODY" | json_field "refreshToken")
if [[ -n "$ROTATED_REFRESH_TOKEN" && "$ROTATED_REFRESH_TOKEN" != "$REFRESH_TOKEN" ]]; then
    TMP_ACTIVATION="${ACTIVATION_FILE}.tmp"
    python3 - "$ACTIVATION_FILE" "$ROTATED_REFRESH_TOKEN" <<'PY' > "$TMP_ACTIVATION"
import json
import sys

path, token = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["refreshToken"] = token
print(json.dumps(data, indent=2, sort_keys=True))
PY
    mv "$TMP_ACTIVATION" "$ACTIVATION_FILE"
    chmod 600 "$ACTIVATION_FILE"
    echo -e "${GREEN}Updated rotated refresh token in ${ACTIVATION_FILE}${NC}"
fi

restart_api

echo
echo -e "${GREEN}License renewal complete.${NC}"
