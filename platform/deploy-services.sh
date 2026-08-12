#!/usr/bin/env bash
set -euo pipefail

# Deploy notes, dmarcer, kubeman to EC2
NOTES_IMAGE="${1:?Usage: deploy-services.sh <notes-image> <dmarcer-image> <kubeman-image>}"
DMARCER_IMAGE="${2}"
KUBEMAN_IMAGE="${3}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
PLATFORM_DIR="${PLATFORM_DIR:-/opt/platform}"

for command_name in docker; do
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

# Pull all images (assumes EC2 instance has ECR credentials configured)
echo "Pulling images from ECR..."
docker pull "${NOTES_IMAGE}" || true
docker pull "${DMARCER_IMAGE}" || true
docker pull "${KUBEMAN_IMAGE}" || true

# Deploy via compose
echo "Deploying services..."
export NOTES_IMAGE DMARCER_IMAGE KUBEMAN_IMAGE

docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --project-name maimons-platform \
  -f "${PLATFORM_DIR}/compose.yaml" \
  pull notes dmarcer kubeman

docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --project-name maimons-platform \
  -f "${PLATFORM_DIR}/compose.yaml" \
  up --detach --no-build --remove-orphans notes dmarcer kubeman

# Health check
echo "Waiting for service health checks..."
for service_port in "notes:3002" "dmarcer:3004" "kubeman:3003"; do
  service_name="${service_port%:*}"
  port="${service_port#*:}"

  for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1 || \
       curl --fail --silent --show-error "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
      echo "✓ ${service_name} is healthy"
      break
    fi
    if [ $attempt -eq 30 ]; then
      echo "ERROR: ${service_name} health check failed after 30 attempts" >&2
      docker compose \
        --project-directory "${PLATFORM_DIR}" \
        --project-name maimons-platform \
        -f "${PLATFORM_DIR}/compose.yaml" \
        ps
      exit 1
    fi
    sleep 2
  done
done

echo "✓ All services deployed and healthy"
