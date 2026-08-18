#!/usr/bin/env bash
set -euo pipefail

SERVICE="monitoring"
DOCKER_DIR="$(cd "$(dirname "$0")/platform/monitoring" && pwd)"
AWS_REGION="eu-central-1"
COMPOSE_DIR="$(dirname "$0")/platform"
ECR_BASE="236565801201.dkr.ecr.eu-central-1.amazonaws.com/monitoring"
TAG="${MONITORING_TAG:-$(date +%Y%m%d-%H%M%S)}"
ECR_IMAGE="$ECR_BASE:$TAG"

# Parse operations
BUILD_ONLY=0
PUSH_ONLY=0
DEPLOY_ONLY=0
STOP_ONLY=0
ALL_OPS=1

while [[ $# -gt 0 ]]; do
  case $1 in
    --build-only) BUILD_ONLY=1; ALL_OPS=0; shift ;;
    --push-only) PUSH_ONLY=1; ALL_OPS=0; shift ;;
    --deploy-only) DEPLOY_ONLY=1; ALL_OPS=0; shift ;;
    --stop-only) STOP_ONLY=1; ALL_OPS=0; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ $STOP_ONLY -eq 1 ]]; then
  echo "Stopping $SERVICE..."
  cd "$COMPOSE_DIR"
  docker compose stop "$SERVICE" || true
  exit 0
fi

if [[ $BUILD_ONLY -eq 1 || $ALL_OPS -eq 1 ]]; then
  echo "=========================================="
  echo "Building $SERVICE"
  echo "=========================================="
  docker build --platform linux/amd64 -t "$ECR_IMAGE" "$DOCKER_DIR/app/" || {
    echo "❌ Build failed"
    exit 1
  }
  echo "✓ Build complete"
fi

if [[ $PUSH_ONLY -eq 1 || $ALL_OPS -eq 1 ]]; then
  echo ""
  echo "=========================================="
  echo "Pushing $SERVICE to ECR"
  echo "=========================================="
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$(echo "$ECR_IMAGE" | cut -d/ -f1)" >/dev/null 2>&1
  docker push "$ECR_IMAGE" || {
    echo "❌ Push failed"
    exit 1
  }
  echo "✓ Push complete"
fi

if [[ $DEPLOY_ONLY -eq 1 || $ALL_OPS -eq 1 ]]; then
  echo ""
  echo "=========================================="
  echo "Deploying $SERVICE"
  echo "=========================================="
  echo "Image: $ECR_IMAGE"
  echo "Version: $TAG"
  echo ""
  cd "$COMPOSE_DIR"

  # ECR login
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$(echo "$ECR_IMAGE" | cut -d/ -f1)" >/dev/null 2>&1

  # Pull fresh image
  docker pull "$ECR_IMAGE"

  # Stop and remove old container
  docker compose stop "$SERVICE" 2>/dev/null || true
  docker compose rm -f "$SERVICE" 2>/dev/null || true

  # Start with env var overrides (MONITORING_VERSION shows the tag in GUI, MONITORING_TAG for compose)
  MONITORING_IMAGE="$ECR_IMAGE" MONITORING_VERSION="$TAG" MONITORING_TAG="$TAG" docker compose up -d "$SERVICE"

  # Wait for health
  echo "→ Waiting for service..."
  for i in {1..30}; do
    if curl -sf "http://127.0.0.1:3000/healthz" >/dev/null 2>&1; then
      echo "✓ $SERVICE healthy"
      docker compose ps "$SERVICE" | tail -1
      exit 0
    fi
    printf "[%2d/30]\r" "$i"
    sleep 1
  done

  echo "❌ Health check failed" >&2
  docker compose logs "$SERVICE" | tail -10 >&2
  exit 1
fi

echo "Done"
