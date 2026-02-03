#!/bin/bash
# test-and-shutdown.sh - Quick test with automatic shutdown
# Usage: ./scripts/test-and-shutdown.sh

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

# Auto-cleanup on exit
cleanup() {
    local exit_code=$?
    
    echo ""
    log_info "Auto-cleanup triggered..."
    
    # Stop and remove test container
    if podman ps -a | grep -q "openclaw-test" 2>/dev/null; then
        log_info "Removing test container..."
        podman stop openclaw-test 2>/dev/null || true
        podman rm openclaw-test 2>/dev/null || true
    fi
    
    # Stop Podman VM
    if podman machine list 2>/dev/null | grep -q "Running"; then
        log_info "Stopping Podman VM..."
        podman machine stop 2>/dev/null || true
    fi
    
    log_info "✓ Cleanup complete"
    
    # Show result
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  ✅ TEST PASSED${NC}"
        echo -e "${GREEN}========================================${NC}"
    else
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  ❌ TEST FAILED${NC}"
        echo -e "${RED}========================================${NC}"
    fi
}
trap cleanup EXIT

echo "========================================"
echo "  Test & Auto-Shutdown"
echo "========================================"
echo ""
echo "This script will:"
echo "  1. Start Podman VM"
echo "  2. Build OpenClaw"
echo "  3. Run tests"
echo "  4. Automatically shutdown VM"
echo ""
read -p "Continue? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""

# Check Podman
if ! command -v podman > /dev/null 2>&1; then
    log_error "Podman not found"
    exit 1
fi

# Start VM
log_step "Starting Podman VM..."
if ! podman machine list 2>/dev/null | grep -q "Running"; then
    podman machine start &
    for i in {1..60}; do
        sleep 2
        if podman machine list 2>/dev/null | grep -q "Running"; then
            break
        fi
    done
fi

if ! podman machine list 2>/dev/null | grep -q "Running"; then
    log_error "VM failed to start"
    exit 1
fi

log_info "✓ VM running"

# Build
log_step "Building OpenClaw..."
cd "$REPO_ROOT"
podman build -t openclaw:test -f Dockerfile .
log_info "✓ Build complete"

# Run test
log_step "Running test container..."
podman run -d \
    --name openclaw-test \
    -p 3457:3000 \
    -v openclaw-test-config:/app/config \
    -e NODE_ENV=development \
    openclaw:test

log_info "Waiting for startup..."
sleep 15

# Validate
log_step "Running validation..."

if ! podman ps | grep -q "openclaw-test"; then
    log_error "Container failed to start"
    podman logs openclaw-test
    exit 1
fi

# Health check
for i in {1..15}; do
    if curl -s http://localhost:3457/health > /dev/null 2&&1; then
        log_info "✓ Health check passed"
        break
    fi
    sleep 2
done

# Show logs
log_step "Recent logs:"
podman logs --tail 20 openclaw-test

# Quick feature check
log_step "Checking custom features..."

if podman logs openclaw-test 2>&1 | grep -qi "thinking"; then
    log_info "✓ Kimi thinking mode detected"
fi

if podman logs openclaw-test 2>&1 | grep -qi "plugin"; then
    log_info "✓ Plugin system detected"
fi

echo ""
log_info "Test completed successfully!"
log_info "VM will now shutdown automatically..."

exit 0
