#!/usr/bin/env bash
set -euo pipefail

IMAGE_URI="${1:?Usage: deploy.sh <ecr-image-uri>}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
PLATFORM_DIR="${PLATFORM_DIR:-/opt/platform}"
RUNTIME_SECRET_NAME="${RUNTIME_SECRET_NAME:-/platform/prod/monitoring/runtime}"

if [[ ! "${IMAGE_URI}" =~ ^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/monitoring:[0-9a-f]{40}$ ]]; then
  echo "ERROR: Invalid immutable monitoring image URI" >&2
  exit 1
fi

for command_name in aws curl docker jq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose v2 is unavailable" >&2
  exit 1
fi

install -d -m 0755 "${PLATFORM_DIR}"

registry="${IMAGE_URI%%/*}"
aws ecr get-login-password --region "${AWS_REGION}" |
  docker login --username AWS --password-stdin "${registry}"

runtime_json="$(aws secretsmanager get-secret-value \
  --secret-id "${RUNTIME_SECRET_NAME}" \
  --region "${AWS_REGION}" \
  --query SecretString \
  --output text)"

if ! jq -e '
  type == "object" and
  (.cloudflare_api_token | type == "string" and length > 0) and
  (.cloudflare_zone_id | type == "string" and length > 0) and
  (.cloudflare_zone_name | type == "string" and length > 0) and
  (.cloudflare_hostnames | type == "string" and length > 0)
' >/dev/null <<<"${runtime_json}"; then
  echo "ERROR: Monitoring runtime secret is missing required values" >&2
  exit 1
fi

for field_name in cloudflare_api_token cloudflare_zone_id cloudflare_zone_name cloudflare_hostnames; do
  field_value="$(jq -r --arg field_name "${field_name}" '.[$field_name]' <<<"${runtime_json}")"
  if [[ "${field_value}" == *$'\n'* || "${field_value}" == *$'\r'* ]]; then
    echo "ERROR: Runtime secret field contains a newline: ${field_name}" >&2
    exit 1
  fi
done

umask 077
{
  printf 'MONITORING_IMAGE=%s\n' "${IMAGE_URI}"
  printf 'CLOUDFLARE_ANALYTICS_API_TOKEN=%s\n' "$(jq -r '.cloudflare_api_token' <<<"${runtime_json}")"
  printf 'CLOUDFLARE_ANALYTICS_ZONE_ID=%s\n' "$(jq -r '.cloudflare_zone_id' <<<"${runtime_json}")"
  printf 'CLOUDFLARE_ANALYTICS_ZONE_NAME=%s\n' "$(jq -r '.cloudflare_zone_name' <<<"${runtime_json}")"
  printf 'CLOUDFLARE_ANALYTICS_HOSTNAMES=%s\n' "$(jq -r '.cloudflare_hostnames' <<<"${runtime_json}")"
} >"${PLATFORM_DIR}/.env"

docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --file "${PLATFORM_DIR}/compose.yaml" \
  pull monitoring docker-proxy

docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --file "${PLATFORM_DIR}/compose.yaml" \
  up --detach --no-build --remove-orphans

for attempt in $(seq 1 30); do
  if curl --fail --silent --show-error http://127.0.0.1:3001/healthz >/dev/null; then
    echo "Monitoring deployment is healthy"
    exit 0
  fi
  echo "Waiting for monitoring health check (${attempt}/30)"
  sleep 2
done

echo "ERROR: Monitoring health check failed" >&2
docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --file "${PLATFORM_DIR}/compose.yaml" \
  ps
exit 1
