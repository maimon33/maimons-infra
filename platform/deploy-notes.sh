#!/usr/bin/env bash
set -euo pipefail

IMAGE_URI="${1:?Usage: deploy-notes.sh <ecr-image-uri>}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
PLATFORM_DIR="${PLATFORM_DIR:-/opt/platform}"

if [[ ! "${IMAGE_URI}" =~ ^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/notes:[a-zA-Z0-9]+$ ]]; then
  echo "ERROR: Invalid notes image URI" >&2
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

umask 077
printf 'NOTES_IMAGE=%s\n' "${IMAGE_URI}" >"${PLATFORM_DIR}/.env.notes"

docker pull "${IMAGE_URI}"

docker run --rm --name notes-check \
  --entrypoint sh \
  -c 'sleep 1' \
  "${IMAGE_URI}" >/dev/null

docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --project-name maimons-platform \
  -f "${PLATFORM_DIR}/compose.yaml" \
  up --detach notes 2>/dev/null || true

for attempt in $(seq 1 30); do
  if curl --fail --silent --show-error http://127.0.0.1:3002/healthz >/dev/null; then
    echo "Notes deployment is healthy"
    exit 0
  fi
  echo "Waiting for notes health check (${attempt}/30)"
  sleep 2
done

echo "ERROR: Notes health check failed" >&2
docker compose \
  --project-directory "${PLATFORM_DIR}" \
  --project-name maimons-platform \
  -f "${PLATFORM_DIR}/compose.yaml" \
  ps notes
exit 1
