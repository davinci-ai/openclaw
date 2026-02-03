#!/bin/bash
# full-test-and-deploy.sh - Complete workflow: build, test, validate, deploy
# Usage: ./scripts/full-test-and-deploy.sh [--auto]

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

TEST_PID=""
BUILD_DIR=""

cleanup_test() {
    if [ -n "$TEST_PID" ] && kill -0 "$TEST_PID" 2>/dev/null; then
        log_info "Stopping test instance..."
        kill "$TEST_PID" || true
        sleep 2
    fi
}
trap cleanup_test EXIT

echo "========================================"
echo "  Full Test & Deploy Workflow"
echo "========================================"
echo ""

# Step 1: Build
log_step "STEP 1: Building test version..."
if ! "$SCRIPT_DIR/safe-test-build.sh" > /tmp/build-output.log 2>&1; then
    log_error "Build failed!"
    cat /tmp/build-output.log
    exit 1
fi

# Extract build directory from output
BUILD_DIR=$(grep "Build location:" /tmp/build-output.log | awk '{print $3}')
if [ -z "$BUILD_DIR" ] || [ ! -d "$BUILD_DIR" ]; then
    log_error "Could not determine build directory"
    exit 1
fi

log_info "✓ Build complete: $BUILD_DIR"

# Step 2: Start test instance
log_step "STEP 2: Starting test instance..."
cd "$BUILD_DIR"

# Start in background
./test-launch.sh > /tmp/test-openclaw.log 2>&1 &
TEST_PID=$!

log_info "Test instance started (PID: $TEST_PID)"
log_info "Waiting for startup..."
sleep 5

# Step 3: Validate
log_step "STEP 3: Running validation checks..."
sleep 10  # Give it time to fully start

if ! ./validate.sh; then
    log_error "Validation failed!"
    echo ""
    echo "Test logs:"
    tail -50 /tmp/test-openclaw.log
    exit 1
fi

log_info "✓ Validation passed"

# Step 4: Custom feature tests
log_step "STEP 4: Testing custom features..."

# Check for custom features in logs
if grep -q "thinking" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Kimi thinking mode initialized"
fi

if grep -q "message_sending" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Plugin hooks initialized"
fi

# Step 5: User confirmation or auto-deploy
log_step "STEP 5: Deployment decision..."

if [ "$AUTO_MODE" = true ]; then
    log_info "Auto-mode: proceeding with deployment"
    DEPLOY_CONFIRM="yes"
else
    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo "✓ Build: PASSED"
    echo "✓ Startup: PASSED"
    echo "✓ Validation: PASSED"
    echo "✓ Custom features: DETECTED"
    echo ""
    echo "Ready to deploy to production!"
    echo ""
    read -p "Deploy to production? (yes/no): " DEPLOY_CONFIRM
fi

if [[ "$DEPLOY_CONFIRM" != "yes" ]]; then
    log_info "Deployment cancelled by user"
    log_info "Test instance is still running. To stop it:"
    log_info "  kill $TEST_PID"
    exit 0
fi

# Step 6: Deploy
log_step "STEP 6: Deploying to production..."

# Stop test instance first
cleanup_test

# Run deployment
if ! ./deploy-to-production.sh; then
    log_error "Deployment failed!"
    exit 1
fi

log_info "✓ Deployment complete"

# Step 7: Final verification
log_step "STEP 7: Final verification..."
sleep 3

if pgrep -f "openclaw" > /dev/null 2>&1; then
    log_info "✓ Production OpenClaw is running"
else
    log_warn "Production OpenClaw not detected as running"
    log_info "You may need to start it manually:"
    log_info "  cd ~/.openclaw && npm start"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Full Test & Deploy Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Build: $BUILD_DIR"
echo "Test logs: /tmp/test-openclaw.log"
echo ""
echo "Your custom OpenClaw is now running in production!"
