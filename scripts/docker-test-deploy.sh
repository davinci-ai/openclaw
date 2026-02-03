#!/bin/bash
# docker-test-deploy.sh - Docker-based testing and deployment
# Usage: ./scripts/docker-test-deploy.sh [test|deploy|rollback]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# Function to test
test_build() {
    log_step "Building test Docker image..."
    
    cd "$REPO_ROOT"
    
    # Build test image
    docker build -t openclaw:test -f Dockerfile .
    
    log_info "✓ Test image built"
    
    # Start test container
    log_step "Starting test container..."
    docker-compose --profile test up -d openclaw-test
    
    log_info "✓ Test container started"
    log_info "Waiting for startup..."
    sleep 15
    
    # Validate
    log_step "Validating test container..."
    
    # Check if container is running
    if ! docker ps | grep -q "openclaw-test"; then
        log_error "Test container not running!"
        docker logs openclaw-test
        docker-compose --profile test down
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
    docker logs --tail 30 openclaw-test
    
    echo ""
    log_info "========================================"
    log_info "Test container is ready!"
    log_info "========================================"
    echo ""
    echo "Access: http://localhost:3457"
    echo "Logs: docker logs -f openclaw-test"
    echo ""
    echo "To stop test: docker-compose --profile test down"
    echo "To deploy: ./scripts/docker-test-deploy.sh deploy"
}

# Function to deploy
deploy() {
    log_step "Deploying to production..."
    
    # Check if test container is running
    if docker ps | grep -q "openclaw-test"; then
        log_warn "Test container is still running"
        read -p "Did you test successfully? (yes/no): " tested
        if [[ "$tested" != "yes" ]]; then
            log_info "Please test first: ./scripts/docker-test-deploy.sh test"
            exit 0
        fi
    fi
    
    # Tag the test image as production
    log_step "Tagging image for production..."
    docker tag openclaw:test openclaw:prod-$(date +%Y%m%d-%H%M%S)
    docker tag openclaw:test openclaw:prod-latest
    
    # Stop production
    log_step "Stopping production container..."
    docker-compose stop openclaw-prod || true
    
    # Rebuild production with latest
    log_step "Building production container..."
    docker-compose up -d --build openclaw-prod
    
    log_info "✓ Production deployed"
    
    # Wait and check
    sleep 10
    
    if docker ps | grep -q "openclaw-production"; then
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
        docker logs openclaw-production
        exit 1
    fi
    
    echo ""
    log_info "========================================"
    log_info "Deployment Complete!"
    log_info "========================================"
    echo ""
    echo "Production: http://localhost:3000"
    echo "Logs: docker logs -f openclaw-production"
}

# Function to rollback
rollback() {
    log_step "Rolling back production..."
    
    # List available images
    echo "Available production images:"
    docker images openclaw:prod-* --format "{{.Tag}}" | head -10 | nl
    echo ""
    
    read -p "Enter image tag to rollback to (or 'latest' for previous): " tag
    
    if [ "$tag" = "latest" ]; then
        # Get second most recent
        tag=$(docker images openclaw:prod-* --format "{{.Tag}}" | head -2 | tail -1)
    fi
    
    if ! docker images "openclaw:$tag" --format "{{.Tag}}" | grep -q .; then
        log_error "Image tag not found: $tag"
        exit 1
    fi
    
    # Stop current production
    docker-compose stop openclaw-prod
    
    # Tag rollback image as latest
    docker tag "openclaw:$tag" openclaw:prod-latest
    
    # Restart
    docker-compose up -d openclaw-prod
    
    log_info "✓ Rolled back to $tag"
}

# Function to cleanup
cleanup() {
    log_step "Cleaning up..."
    docker-compose --profile test down
    docker rmi openclaw:test 2>/dev/null || true
    log_info "✓ Cleanup complete"
}

# Main
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
        echo "Commands:"
        echo "  test     - Build and start test container"
        echo "  deploy   - Deploy to production (after testing)"
        echo "  rollback - Rollback to previous version"
        echo "  cleanup  - Remove test containers and images"
        exit 1
        ;;
esac
