#!/usr/bin/env bash
set -euo pipefail

# Build and push monitoring app to ECR
#
# Usage:
#   ./build-and-push.sh [TAG]
#
# Environment variables:
#   AWS_REGION         AWS region (default: eu-central-1)
#   AWS_ACCOUNT_ID     AWS account ID (default: 236565801201)
#   ECR_REPOSITORY     ECR repository name (default: monitoring)
#
# Examples:
#   ./build-and-push.sh                    # Uses git SHA as tag
#   ./build-and-push.sh latest             # Tag as 'latest'
#   ./build-and-push.sh v1.2.3             # Tag as 'v1.2.3'

readonly AWS_REGION="${AWS_REGION:-eu-central-1}"
readonly AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-236565801201}"
readonly ECR_REPOSITORY="${ECR_REPOSITORY:-monitoring}"
readonly IMAGE_TAG="${1:-$(git rev-parse --short HEAD)}"
readonly ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
readonly IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}→${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

# Verify we're in the right directory
if [[ ! -f "app/Dockerfile" ]]; then
  log_error "Dockerfile not found at app/Dockerfile"
  log_error "Run this script from platform/monitoring/ directory"
  exit 1
fi

log_info "Building monitoring app"
log_info "  Region:     ${AWS_REGION}"
log_info "  Account:    ${AWS_ACCOUNT_ID}"
log_info "  Repository: ${ECR_REPOSITORY}"
log_info "  Tag:        ${IMAGE_TAG}"
log_info "  Full URI:   ${IMAGE_URI}"
echo ""

# Build Docker image
log_info "Building Docker image..."
docker build --tag "${IMAGE_URI}" app

# Login to ECR
log_info "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}" > /dev/null

# Push to ECR
log_info "Pushing to ECR..."
docker push "${IMAGE_URI}"

echo ""
log_info "Successfully pushed ${IMAGE_URI}"
echo ""
echo "Next steps:"
echo "  1. Deploy via GitHub Actions: push to main or trigger workflow_dispatch"
echo "  2. Or deploy manually via SSM:"
echo "     aws ssm send-command \\"
echo "       --instance-ids i-0103a5cecf6618658 \\"
echo "       --document-name AWS-RunShellScript \\"
echo "       --parameters 'commands=[\"docker pull ${IMAGE_URI} && docker-compose -f /opt/platform/compose.yaml up -d monitoring\"]'"
