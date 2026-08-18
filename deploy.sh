#!/usr/bin/env bash
set -eo pipefail

# Central deployment script for all maimons services
# Usage: ./deploy.sh <service> <operation> [--tag TAG]
# Services: monitoring, notes, dmarcer, kubeman, mosar
# Operations: build, push, deploy, stop, restart, build-push-deploy, logs

AWS_REGION="eu-central-1"
ECR_ACCOUNT="236565801201"
ECR_REGISTRY="${ECR_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Get service config
get_service_repo() {
  case "$1" in
    monitoring) echo "maimons-infra/platform/monitoring" ;;
    notes) echo "notes" ;;
    dmarcer) echo "dmarcer" ;;
    kubeman) echo "kube-man" ;;
    mosar) echo "mosar.maimons.org" ;;
    *) return 1 ;;
  esac
}

get_compose_path() {
  case "$1" in
    monitoring) echo "maimons-infra/platform/monitoring/compose.yaml" ;;
    notes) echo "notes/compose.yaml" ;;
    dmarcer) echo "dmarcer/compose.yaml" ;;
    kubeman) echo "kube-man/compose.yaml" ;;
    mosar) echo "mosar.maimons.org/compose.yaml" ;;
    *) return 1 ;;
  esac
}

get_dockerfile_path() {
  case "$1" in
    monitoring) echo "maimons-infra/platform/monitoring/app/Dockerfile" ;;
    notes) echo "notes/Dockerfile" ;;
    dmarcer) echo "dmarcer/Dockerfile" ;;
    kubeman) echo "kube-man/docker/Dockerfile.web" ;;
    mosar) echo "mosar.maimons.org/Dockerfile" ;;
    *) return 1 ;;
  esac
}

get_port() {
  case "$1" in
    monitoring) echo "3000" ;;
    notes) echo "3002" ;;
    dmarcer) echo "3004" ;;
    kubeman) echo "3003" ;;
    mosar) echo "3001" ;;
    *) return 1 ;;
  esac
}

# Parse arguments
SERVICE="${1:-}"
OPERATION="${2:-}"
TAG="${TAG:-}"

# Parse --tag flag if provided
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag) TAG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SERVICE" ]] || [[ -z "$OPERATION" ]]; then
  echo "Usage: $0 <service> <operation> [--tag TAG]"
  echo ""
  echo "Services: monitoring, notes, dmarcer, kubeman, mosar"
  echo "Operations:"
  echo "  build                 - Build docker image"
  echo "  push                  - Push to ECR"
  echo "  deploy                - Deploy container"
  echo "  stop                  - Stop container"
  echo "  restart               - Restart container"
  echo "  logs                  - Follow logs"
  echo "  build-push-deploy     - Build, push, and deploy"
  exit 1
fi

# Get service config
SERVICE_REPO=$(get_service_repo "$SERVICE") || {
  echo "❌ Unknown service: $SERVICE"
  exit 1
}

COMPOSE_PATH=$(get_compose_path "$SERVICE")
DOCKERFILE_REL=$(get_dockerfile_path "$SERVICE")
PORT=$(get_port "$SERVICE")
ECR_IMAGE="${ECR_REGISTRY}/${SERVICE}"

# Generate tag if not provided
if [[ -z "$TAG" ]]; then
  TAG="$(date +%Y%m%d-%H%M%S)"
fi

# Find repo root (parent of maimons-infra)
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${REPO_ROOT}/../${SERVICE_REPO}"

# Ensure compose file exists
if [[ ! -f "${REPO_ROOT}/../${COMPOSE_PATH}" ]]; then
  echo "❌ Compose file not found: ${COMPOSE_PATH}"
  exit 1
fi

# Functions
build_image() {
  echo "=========================================="
  echo "Building ${SERVICE}"
  echo "=========================================="

  DOCKERFILE_PATH="${REPO_ROOT}/../${DOCKERFILE_REL}"

  if [[ ! -f "$DOCKERFILE_PATH" ]]; then
    echo "❌ Dockerfile not found: $DOCKERFILE_REL"
    exit 1
  fi

  docker build --platform linux/amd64 -f "$DOCKERFILE_PATH" -t "${ECR_IMAGE}:${TAG}" -t "${ECR_IMAGE}:latest" "$REPO_DIR" || {
    echo "❌ Build failed"
    exit 1
  }
  echo "✓ Build complete: ${ECR_IMAGE}:${TAG} (also tagged as latest)"
}

push_image() {
  echo ""
  echo "=========================================="
  echo "Pushing ${SERVICE} to ECR"
  echo "=========================================="

  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null 2>&1

  docker push "${ECR_IMAGE}:${TAG}" || {
    echo "❌ Push failed"
    exit 1
  }
  docker push "${ECR_IMAGE}:latest" || {
    echo "❌ Push latest tag failed"
    exit 1
  }
  echo "✓ Push complete: ${TAG} and latest"
}

deploy_service() {
  echo ""
  echo "=========================================="
  echo "Deploying ${SERVICE}"
  echo "=========================================="
  echo "Image: ${ECR_IMAGE}:latest (tag: ${TAG})"
  echo ""

  # ECR login
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null 2>&1

  # Pull fresh latest image
  docker pull "${ECR_IMAGE}:latest"

  # Stop and remove old container
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" stop "$SERVICE" 2>/dev/null || true
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" rm -f "$SERVICE" 2>/dev/null || true

  # Deploy with env vars (using latest tag)
  SERVICE_TAG="${TAG}" \
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" up -d "$SERVICE"

  # Wait for health
  echo "→ Waiting for service..."
  for i in {1..30}; do
    if curl -sf "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
      echo "✓ ${SERVICE} healthy"
      docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" ps "$SERVICE" | tail -1
      exit 0
    fi
    printf "[%2d/30]\r" "$i"
    sleep 1
  done

  echo "❌ Health check failed" >&2
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" logs "$SERVICE" | tail -10 >&2
  exit 1
}

stop_service() {
  echo "Stopping ${SERVICE}..."
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" stop "$SERVICE" || true
  echo "✓ Stopped"
}

restart_service() {
  echo "Restarting ${SERVICE}..."
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" restart "$SERVICE"
  echo "✓ Restarted"
}

show_logs() {
  docker compose -f "${REPO_ROOT}/../${COMPOSE_PATH}" logs -f "$SERVICE"
}

# Execute operation
case "$OPERATION" in
  build)
    build_image
    ;;
  push)
    push_image
    ;;
  deploy)
    deploy_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    restart_service
    ;;
  logs)
    show_logs
    ;;
  build-push-deploy)
    build_image
    push_image
    deploy_service
    ;;
  *)
    echo "❌ Unknown operation: $OPERATION"
    exit 1
    ;;
esac
