#!/bin/bash
# quick-test-build.sh - On-demand Podman testing (VM starts/stops automatically)
# Usage: ./scripts/quick-test-build.sh

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

# Cleanup function - stops VM when done
cleanup() {
    log_info "Cleaning up..."
    
    # Stop test container if running
    if podman ps | grep -q "openclaw-test" 2>/dev/null; then
        log_info "Stopping test container..."
        podman stop openclaw-test 2>/dev/null || true
        podman rm openclaw-test 2>/dev/null || true
    fi
    
    # Stop Podman VM to save resources
    if podman machine list | grep -q "Running" 2>/dev/null; then
        log_info "Stopping Podman VM to save resources..."
        podman machine stop 2>/dev/null || true
    fi
    
    log_info "✓ Cleanup complete"
}
trap cleanup EXIT

echo "========================================"
echo "  Quick Test Build (On-Demand)"
echo "========================================"
echo ""

# Check if Podman is installed
if ! command -v podman > /dev/null 2>&1; then
    log_error "Podman not found. Run ./scripts/setup-podman-macos.sh first"
    exit 1
fi

# Step 1: Start Podman VM
log_step "Step 1: Starting Podman VM..."

if podman machine list | grep -q "Running" 2>/dev/null; then
    log_info "✓ Podman VM already running"
else
    log_info "Starting Podman VM (this may take a minute)..."
    podman machine start &
    START_PID=$!
    
    # Wait for VM with timeout
    for i in {1..60}; do
        if podman machine list | grep -q "Running" 2>/dev/null; then
            log_info "✓ Podman VM is running"
            break
        fi
        sleep 2
    done
    
    if ! podman machine list | grep -q "Running" 2>/dev/null; then
        log_error "Podman VM failed to start within 2 minutes"
        kill $START_PID 2>/dev/null || true
        exit 1
    fi
fi

# Step 2: Build
log_step "Step 2: Building OpenClaw..."
cd "$REPO_ROOT"

if ! podman build -t openclaw:test -f Dockerfile .; then
    log_error "Build failed!"
    exit 1
fi

log_info "✓ Build complete"

# Step 3: Run test container
log_step "Step 3: Starting test container..."
podman run -d \
    --name openclaw-test \
    -p 3457:3000 \
    -v openclaw-test-config:/app/config \
    -v openclaw-test-data:/app/data \
    -e NODE_ENV=development \
    -e PORT=3000 \
    openclaw:test

log_info "✓ Test container started"
log_info "Waiting for startup..."
sleep 15

# Step 4: Validate
log_step "Step 4: Validating..."

# Check if running
if ! podman ps | grep -q "openclaw-test"; then
    log_error "Test container failed!"
    podman logs openclaw-test
    exit 1
fi

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
    podman logs --tail 50 openclaw-test
    exit 1
fi

log_info "✓ Health check passed"

# Step 5: Show status
log_step "Step 5: Test Results"
echo ""
echo "========================================"
echo "  ✅ OpenClaw Test Instance Ready!"
echo "========================================"
echo ""
echo "URL: http://localhost:3457"
echo "Logs: podman logs -f openclaw-test"
echo ""
echo "Test your custom features:"
echo "  - Kimi thinking mode"
echo "  - Plugin hooks"
echo "  - apiId mapping"
echo ""
echo "========================================"
echo ""

# Ask user what to do next
echo "What would you like to do?"
echo ""
echo "1) Deploy to production (stops test VM after)"
echo "2) Stop test and cleanup (VM will stop)"
echo "3) Keep test running (VM stays on)"
echo ""
read -p "Choice (1/2/3): " choice

case $choice in
    1)
        log_step "Deploying to production..."
        
        # Stop test container
        podman stop openclaw-test
        podman rm openclaw-test
        
        # Tag for production
        podman tag openclaw:test "openclaw:prod-$(date +%Y%m%d-%H%M%S)"
        podman tag openclaw:test openclaw:prod-latest
        
        # Stop VM temporarily
        log_info "Stopping VM before production deployment..."
        podman machine stop
        
        # Deploy to production (non-container)
        log_info "Deploying to production..."
        cd "$REPO_ROOT"
        
        # Backup current production
        PROD_DIR="${HOME}/.openclaw"
        BACKUP_DIR="${HOME}/.openclaw-backup-$(date +%Y%m%d-%H%M%S)"
        
        if [ -d "$PROD_DIR/dist" ]; then
            mkdir -p "$BACKUP_DIR"
            cp -r "$PROD_DIR/dist" "$BACKUP_DIR/"
            log_info "✓ Backup created: $BACKUP_DIR"
        fi
        
        # Build for production
        npm ci
        npm run build
        
        # Deploy
        cp -r "$REPO_ROOT/dist" "$PROD_DIR/"
        
        log_info "✓ Deployed to production"
        log_info "Start with: cd ~/.openclaw && npm start"
        ;;
    2)
        log_info "Stopping test and cleaning up..."
        # Cleanup will run via trap
        ;;
    3)
        log_info "Keeping test running..."
        log_info "VM will stay on. Access at: http://localhost:3457"
        log_info "To stop later: podman machine stop"
        # Disable cleanup trap
        trap - EXIT
        ;;
    *)
        log_warn "Invalid choice, cleaning up..."
        ;;
esac

echo ""
log_info "Done!"
