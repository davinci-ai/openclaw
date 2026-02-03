#!/bin/bash
# podman-test-deploy.sh - Podman-based testing and deployment
# Usage: ./scripts/podman-test-deploy.sh [test|deploy|rollback|cleanup]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Use podman if available, fallback to docker
if command -v podman > /dev/null 2>&1; then
    CONTAINER_CMD="podman"
    COMPOSE_CMD="podman-compose"
else
    CONTAINER_CMD="docker"
    COMPOSE_CMD="docker-compose"
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

# Check if podman is available
check_podman() {
    if ! command -v podman > /dev/null 2>&1; then
        log_warn "Podman not found, using Docker as fallback"
        CONTAINER_CMD="docker"
        COMPOSE_CMD="docker-compose"
    else
        log_info "Using Podman (rootless, daemonless)"
        # Check if podman-compose is available
        if ! command -v podman-compose > /dev/null 2>&1; then
            log_warn "podman-compose not found, using podman directly"
            COMPOSE_CMD=""
        fi
    fi
}

# Function to test with podman
test_build() {
    log_step "Building container image with ${CONTAINER_CMD}..."
    
    cd "$REPO_ROOT"
    
    # Build image
    $CONTAINER_CMD build -t openclaw:test -f Dockerfile .
    
    log_info "✓ Image built"
    
    # Start test container
    log_step "Starting test container..."
    
    if [ -n "$COMPOSE_CMD" ] && [ "$COMPOSE_CMD" != "docker-compose" ]; then
        # Use podman-compose
        $COMPOSE_CMD --profile test up -d openclaw-test
    else
        # Use podman run directly
        $CONTAINER_CMD run -d \
            --name openclaw-test \
            -p 3457:3000 \
            -v openclaw-test-config:/app/config \
            -v openclaw-test-data:/app/data \
            -e NODE_ENV=development \
            -e PORT=3000 \
            openclaw:test
    fi
    
    log_info "✓ Test container started"
    log_info "Waiting for startup..."
    sleep 15
    
    # Validate
    log_step "Validating test container..."
    
    # Check if container is running
    if ! $CONTAINER_CMD ps | grep -q "openclaw-test"; then
        log_error "Test container not running!"
        $CONTAINER_CMD logs openclaw-test
        $CONTAINER_CMD rm -f openclaw-test 2>/dev/null || true
        exit 1
    fi
    
    log_info "✓ Test container is running"
    
    # Check health
    for i in {1..10}; do
        if curl -s http://localhost:3457/health > /dev/null 2&&1; then
            log_info "✓ Health check passed"
            break
        fi
        sleep 2
    done
    
    # Show logs
    log_step "Recent logs:"
    $CONTAINER_CMD logs --tail 30 openclaw-test
    
    echo ""
    log_info "========================================"
    log_info "Test container is ready!"
    log_info "========================================"
    echo ""
    echo "Access: http://localhost:3457"
    echo "Logs: $CONTAINER_CMD logs -f openclaw-test"
    echo ""
    echo "To stop test: $CONTAINER_CMD stop openclaw-test && $CONTAINER_CMD rm openclaw-test"
    echo "To deploy: ./scripts/podman-test-deploy.sh deploy"
}

# Function to deploy
deploy() {
    log_step "Deploying to production..."
    
    # Check if test container is running
    if $CONTAINER_CMD ps | grep -q "openclaw-test"; then
        log_warn "Test container is still running"
        read -p "Did you test successfully? (yes/no): " tested
        if [[ "$tested" != "yes" ]]; then
            log_info "Please test first: ./scripts/podman-test-deploy.sh test"
            exit 0
        fi
    fi
    
    # Tag the test image as production
    log_step "Tagging image for production..."
    $CONTAINER_CMD tag openclaw:test "openclaw:prod-$(date +%Y%m%d-%H%M%S)"
    $CONTAINER_CMD tag openclaw:test openclaw:prod-latest
    
    # Stop production
    log_step "Stopping production container..."
    $CONTAINER_CMD stop openclaw-production 2>/dev/null || true
    $CONTAINER_CMD rm openclaw-production 2>/dev/null || true
    
    # Start production
    log_step "Starting production container..."
    $CONTAINER_CMD run -d \
        --name openclaw-production \
        -p 3000:3000 \
        -v openclaw-prod-config:/app/config \
        -v openclaw-prod-data:/app/data \
        -e NODE_ENV=production \
        -e PORT=3000 \
        --restart unless-stopped \
        openclaw:prod-latest
    
    log_info "✓ Production deployed"
    
    # Wait and check
    sleep 10
    
    if $CONTAINER_CMD ps | grep -q "openclaw-production"; then
        log_info "✓ Production container is running"
        
        # Check health
        for i in {1..10}; do
            if curl -s http://localhost:3000/health > /dev/null 2&&1; then
                log_info "✓ Production health check passed"
                break
            fi
            sleep 2
        done
    else
        log_error "Production container failed to start!"
        $CONTAINER_CMD logs openclaw-production
        exit 1
    fi
    
    echo ""
    log_info "========================================"
    log_info "Deployment Complete!"
    log_info "========================================"
    echo ""
    echo "Production: http://localhost:3000"
    echo "Logs: $CONTAINER_CMD logs -f openclaw-production"
}

# Function to rollback
rollback() {
    log_step "Rolling back production..."
    
    # List available images
    echo "Available production images:"
    $CONTAINER_CMD images openclaw:prod-* --format "{{.Tag}}" 2>/dev/null | head -10 | nl || \
        $CONTAINER_CMD images | grep openclaw | grep prod | awk '{print $2}' | head -10 | nl
    echo ""
    
    read -p "Enter image tag to rollback to (or 'latest' for previous): " tag
    
    if [ "$tag" = "latest" ]; then
        # Get second most recent
        tag=$($CONTAINER_CMD images openclaw:prod-* --format "{{.Tag}}" 2>/dev/null | head -2 | tail -1) || \
            tag=$($CONTAINER_CMD images | grep openclaw | grep prod | awk '{print $2}' | head -2 | tail -1)
    fi
    
    if ! $CONTAINER_CMD images "openclaw:$tag" --format "{{.Tag}}" 2>/dev/null | grep -q . && \
       ! $CONTAINER_CMD images | grep -q "openclaw.*$tag"; then
        log_error "Image tag not found: $tag"
        exit 1
    fi
    
    # Stop current production
    $CONTAINER_CMD stop openclaw-production 2>/dev/null || true
    $CONTAINER_CMD rm openclaw-production 2>/dev/null || true
    
    # Tag rollback image as latest
    $CONTAINER_CMD tag "openclaw:$tag" openclaw:prod-latest
    
    # Restart
    $CONTAINER_CMD run -d \
        --name openclaw-production \
        -p 3000:3000 \
        -v openclaw-prod-config:/app/config \
        -v openclaw-prod-data:/app/data \
        -e NODE_ENV=production \
        -e PORT=3000 \
        --restart unless-stopped \
        openclaw:prod-latest
    
    log_info "✓ Rolled back to $tag"
}

# Function to cleanup
cleanup() {
    log_step "Cleaning up..."
    $CONTAINER_CMD stop openclaw-test 2>/dev/null || true
    $CONTAINER_CMD rm openclaw-test 2>/dev/null || true
    $CONTAINER_CMD rmi openclaw:test 2>/dev/null || true
    log_info "✓ Cleanup complete"
}

# Main
check_podman

case "${1:-}" in
    test)
        test_build
        ;;
    deploy)
        deploy
        ;;
    rollback)
        rollback
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Usage: $0 [test|deploy|rollback|cleanup]"
        echo ""
        echo "Container runtime: ${CONTAINER_CMD}"
        echo ""
        echo "Commands:"
        echo "  test     - Build and start test container"
        echo "  deploy   - Deploy to production (after testing)"
        echo "  rollback - Rollback to previous version"
        echo "  cleanup  - Remove test containers and images"
        exit 1
        ;;
esac
