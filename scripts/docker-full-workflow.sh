#!/bin/bash
# docker-full-workflow.sh - Complete Docker-based test and deploy
# Usage: ./scripts/docker-full-workflow.sh [--auto]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_MODE=false

if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "========================================"
echo "  Docker Full Test & Deploy Workflow"
echo "========================================"
echo ""

# Step 1: Build test image
log_step "STEP 1: Building Docker image..."
cd "$SCRIPT_DIR/.."

if ! docker build -t openclaw:test -f Dockerfile .; then
    log_error "Docker build failed!"
    exit 1
fi

log_info "✓ Docker image built"

# Step 2: Start test container
log_step "STEP 2: Starting test container..."
docker-compose --profile test up -d openclaw-test

log_info "Waiting for container to start..."
sleep 15

# Step 3: Validate
log_step "STEP 3: Validating test container..."

# Check container status
if ! docker ps | grep -q "openclaw-test"; then
    log_error "Test container failed to start!"
    docker logs openclaw-test
    docker-compose --profile test down
    exit 1
fi

log_info "✓ Test container is running"

# Health check
HEALTHY=false
for i in {1..15}; do
    if curl -s http://localhost:3457/health > /dev/null 2&&1; then
        HEALTHY=true
        break
    fi
    sleep 2
done

if [ "$HEALTHY" = false ]; then
    log_error "Health check failed!"
    docker logs --tail 50 openclaw-test
    docker-compose --profile test down
    exit 1
fi

log_info "✓ Health check passed"

# Step 4: Show logs
log_step "STEP 4: Recent logs..."
docker logs --tail 30 openclaw-test

# Step 5: User confirmation
log_step "STEP 5: Deployment decision..."

if [ "$AUTO_MODE" = true ]; then
    log_info "Auto-mode: proceeding with deployment"
    DEPLOY="yes"
else
    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo "✓ Docker build: PASSED"
    echo "✓ Container startup: PASSED"
    echo "✓ Health check: PASSED"
    echo ""
    echo "Test URL: http://localhost:3457"
    echo ""
    read -p "Deploy to production? (yes/no): " DEPLOY
fi

if [[ "$DEPLOY" != "yes" ]]; then
    log_info "Deployment cancelled"
    log_info "Test container still running on port 3457"
    log_info "To stop: docker-compose --profile test down"
    exit 0
fi

# Step 6: Deploy
log_step "STEP 6: Deploying to production..."

# Stop test container
docker-compose --profile test down

# Tag for production
docker tag openclaw:test "openclaw:prod-$(date +%Y%m%d-%H%M%S)"
docker tag openclaw:test openclaw:prod-latest

# Deploy
docker-compose up -d --build openclaw-prod

log_info "Waiting for production to start..."
sleep 15

# Verify production
if ! docker ps | grep -q "openclaw-production"; then
    log_error "Production container failed to start!"
    docker logs openclaw-production
    exit 1
fi

# Health check production
for i in {1..15}; do
    if curl -s http://localhost:3000/health > /dev/null 2&&1; then
        log_info "✓ Production health check passed"
        break
    fi
    sleep 2
done

echo ""
log_info "========================================"
log_info "  Deployment Complete!"
log_info "========================================"
echo ""
echo "Production: http://localhost:3000"
echo "Logs: docker logs -f openclaw-production"
echo ""
echo "To rollback:"
echo "  ./scripts/docker-test-deploy.sh rollback"
