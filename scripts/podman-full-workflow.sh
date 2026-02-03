#!/bin/bash
# podman-full-workflow.sh - Complete Podman-based test and deploy
# Usage: ./scripts/podman-full-workflow.sh [--auto]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_MODE=false

if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

# Use podman if available, fallback to docker
if command -v podman > /dev/null 2>&1; then
    CONTAINER_CMD="podman"
    log_info() { echo -e "\033[0;32m[INFO]\033[0m [Podman] $1"; }
else
    CONTAINER_CMD="docker"
    log_info() { echo -e "\033[0;32m[INFO]\033[0m [Docker] $1"; }
fi

log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_step() { echo -e "\033[0;34m[STEP]\033[0m $1"; }

echo "========================================"
echo "  Podman Full Test & Deploy Workflow"
echo "========================================"
echo ""

# Step 1: Build
log_step "STEP 1: Building container image..."
cd "$SCRIPT_DIR/.."

if ! $CONTAINER_CMD build -t openclaw:test -f Dockerfile .; then
    log_error "Container build failed!"
    exit 1
fi

log_info "✓ Container image built"

# Step 2: Start test container
log_step "STEP 2: Starting test container..."
$CONTAINER_CMD run -d \
    --name openclaw-test \
    -p 3457:3000 \
    -v openclaw-test-config:/app/config \
    -v openclaw-test-data:/app/data \
    -e NODE_ENV=development \
    -e PORT=3000 \
    openclaw:test

log_info "Waiting for container to start..."
sleep 15

# Step 3: Validate
log_step "STEP 3: Validating test container..."

# Check container status
if ! $CONTAINER_CMD ps | grep -q "openclaw-test"; then
    log_error "Test container failed to start!"
    $CONTAINER_CMD logs openclaw-test
    $CONTAINER_CMD rm openclaw-test
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
    $CONTAINER_CMD logs --tail 50 openclaw-test
    $CONTAINER_CMD stop openclaw-test
    $CONTAINER_CMD rm openclaw-test
    exit 1
fi

log_info "✓ Health check passed"

# Step 4: Show logs
log_step "STEP 4: Recent logs..."
$CONTAINER_CMD logs --tail 30 openclaw-test

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
    echo "✓ Container build: PASSED"
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
    log_info "To stop: $CONTAINER_CMD stop openclaw-test && $CONTAINER_CMD rm openclaw-test"
    exit 0
fi

# Step 6: Deploy
log_step "STEP 6: Deploying to production..."

# Stop test container
$CONTAINER_CMD stop openclaw-test
$CONTAINER_CMD rm openclaw-test

# Tag for production
$CONTAINER_CMD tag openclaw:test "openclaw:prod-$(date +%Y%m%d-%H%M%S)"
$CONTAINER_CMD tag openclaw:test openclaw:prod-latest

# Stop old production
$CONTAINER_CMD stop openclaw-production 2>/dev/null || true
$CONTAINER_CMD rm openclaw-production 2>/dev/null || true

# Start production
$CONTAINER_CMD run -d \
    --name openclaw-production \
    -p 3000:3000 \
    -v openclaw-prod-config:/app/config \
    -v openclaw-prod-data:/app/data \
    -e NODE_ENV=production \
    -e PORT=3000 \
    --restart unless-stopped \
    openclaw:prod-latest

log_info "Waiting for production to start..."
sleep 15

# Verify production
if ! $CONTAINER_CMD ps | grep -q "openclaw-production"; then
    log_error "Production container failed to start!"
    $CONTAINER_CMD logs openclaw-production
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
echo "Logs: $CONTAINER_CMD logs -f openclaw-production"
echo ""
echo "To rollback:"
echo "  ./scripts/podman-test-deploy.sh rollback"
