#!/bin/bash
# safe-test-build.sh - Build and test custom OpenClaw without affecting production
# Usage: ./scripts/safe-test-build.sh

set -euo pipefail

# Configuration
PROD_DIR="${HOME}/.openclaw"
TEST_DIR="${HOME}/.openclaw-test"
TEST_PORT="${TEST_PORT:-3457}"
TEST_CONFIG_DIR="${TEST_DIR}/config"
BUILD_DIR="/tmp/openclaw-test-build-$$"
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

# Cleanup function
cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        log_info "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}
trap cleanup EXIT

echo "=========================================="
echo "  OpenClaw Safe Test Build & Deploy"
echo "=========================================="
echo ""

# Step 1: Pre-flight checks
log_step "1/8: Pre-flight checks..."

# Check if production OpenClaw is running
if pgrep -f "openclaw" > /dev/null 2&&1 || lsof -Pi :3000 -sTCP:LISTEN > /dev/null 2&&1; then
    log_info "✓ Production OpenClaw detected (will not interfere)"
else
    log_warn "Production OpenClaw not detected (may not be running)"
fi

# Check Node.js version
if ! command -v node > /dev/null 2&&1; then
    log_error "Node.js not found"
    exit 1
fi
NODE_VERSION=$(node --version)
log_info "✓ Node.js version: $NODE_VERSION"

# Step 2: Create isolated build
log_step "2/8: Creating isolated build..."
mkdir -p "$BUILD_DIR"
cp -r "$REPO_ROOT"/* "$BUILD_DIR/"
cd "$BUILD_DIR"
log_info "✓ Build directory created: $BUILD_DIR"

# Step 3: Install dependencies and build
log_step "3/8: Installing dependencies..."
if ! npm ci > /tmp/build-deps.log 2>&1; then
    log_error "Failed to install dependencies"
    cat /tmp/build-deps.log
    exit 1
fi
log_info "✓ Dependencies installed"

log_step "4/8: Building OpenClaw..."
if ! npm run build > /tmp/build.log 2>&1; then
    log_error "Build failed!"
    cat /tmp/build.log
    exit 1
fi
log_info "✓ Build successful"

# Step 4: Create test environment
log_step "5/8: Setting up test environment..."

# Create test config directory
mkdir -p "$TEST_CONFIG_DIR"

# Copy production config as base (but modify for test)
if [ -f "$PROD_DIR/config/config.yaml" ]; then
    cp "$PROD_DIR/config/config.yaml" "$TEST_CONFIG_DIR/config.yaml"
    log_info "✓ Copied production config to test environment"
else
    log_warn "No production config found, will use defaults"
fi

# Create test-specific config overrides
cat > "$TEST_CONFIG_DIR/test-overrides.yaml" << EOF
# Test environment overrides
# This file ensures test instance doesn't conflict with production

server:
  port: $TEST_PORT

# Use test Telegram bot token if available
# Set TEST_BOT_TOKEN environment variable
EOF

# Step 5: Create test launcher script
log_step "6/8: Creating test launcher..."

cat > "$BUILD_DIR/test-launch.sh" << EOF
#!/bin/bash
# Test launcher for isolated OpenClaw instance

export OPENCLAW_CONFIG_DIR="$TEST_CONFIG_DIR"
export OPENCLAW_DATA_DIR="$TEST_DIR/data"
export OPENCLAW_LOG_LEVEL="debug"
export PORT="$TEST_PORT"

# Optional: Use test bot token
if [ -n "\${TEST_BOT_TOKEN:-}" ]; then
    export TELEGRAM_BOT_TOKEN="\$TEST_BOT_TOKEN"
fi

echo "========================================"
echo "  OpenClaw TEST Instance"
echo "========================================"
echo "Config: \$OPENCLAW_CONFIG_DIR"
echo "Port: \$PORT"
echo "PID: \$$"
echo "========================================"
echo ""

# Save PID for cleanup
echo \$$ > "$TEST_DIR/test-instance.pid"

# Start OpenClaw
exec node dist/index.js
EOF

chmod +x "$BUILD_DIR/test-launch.sh"
log_info "✓ Test launcher created"

# Step 6: Create validation script
log_step "7/8: Creating validation script..."

cat > "$BUILD_DIR/validate.sh" << EOF
#!/bin/bash
# Validation script for test OpenClaw instance

TEST_PID_FILE="$TEST_DIR/test-instance.pid"
TEST_PORT="$TEST_PORT"
TIMEOUT=30

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_pass() { echo -e "\${GREEN}✓\${NC} \$1"; }
check_fail() { echo -e "\${RED}✗\${NC} \$1"; }

ERRORS=0

echo "========================================"
echo "  OpenClaw Test Validation"
echo "========================================"
echo ""

# Check 1: Process is running
if [ -f "\$TEST_PID_FILE" ]; then
    PID=\$(cat "\$TEST_PID_FILE")
    if ps -p "\$PID" > /dev/null 2&&1; then
        check_pass "OpenClaw process running (PID: \$PID)"
    else
        check_fail "OpenClaw process not running"
        ((ERRORS++))
    fi
else
    check_fail "PID file not found"
    ((ERRORS++))
fi

# Check 2: Port is listening
echo "Waiting for port \$TEST_PORT..."
for i in \$(seq 1 \$TIMEOUT); do
    if lsof -Pi :"\$TEST_PORT" -sTCP:LISTEN > /dev/null 2&&1; then
        check_pass "Port \$TEST_PORT is listening"
        break
    fi
    sleep 1
done

if ! lsof -Pi :"\$TEST_PORT" -sTCP:LISTEN > /dev/null 2&&1; then
    check_fail "Port \$TEST_PORT not listening after \$TIMEOUT seconds"
    ((ERRORS++))
fi

# Check 3: Log file exists and has no critical errors
LOG_FILE="\${OPENCLAW_LOG_FILE:-$TEST_DIR/data/logs/openclaw.log}"
if [ -f "\$LOG_FILE" ]; then
    if grep -i "error\|fatal\|crash" "\$LOG_FILE" | grep -v "expected\|handled" > /dev/null 2&&1; then
        check_fail "Errors found in log file"
        echo "Recent errors:"
        grep -i "error\|fatal\|crash" "\$LOG_FILE" | tail -5
        ((ERRORS++))
    else
        check_pass "No critical errors in log"
    fi
else
    check_warn "Log file not found yet"
fi

# Check 4: Health endpoint (if available)
if curl -s http://localhost:\$TEST_PORT/health > /dev/null 2&&1; then
    check_pass "Health endpoint responding"
else
    check_warn "Health endpoint not available (may be normal)"
fi

echo ""
if [ \$ERRORS -eq 0 ]; then
    echo -e "\${GREEN}✓ All validation checks passed!\${NC}"
    exit 0
else
    echo -e "\${RED}✗ \$ERRORS validation check(s) failed\${NC}"
    exit 1
fi
EOF

chmod +x "$BUILD_DIR/validate.sh"
log_info "✓ Validation script created"

# Step 7: Create deployment script
log_step "8/8: Creating deployment script..."

cat > "$BUILD_DIR/deploy-to-production.sh" << 'EOF'
#!/bin/bash
# Deploy tested build to production
# Only run this after successful testing!

set -euo pipefail

PROD_DIR="${HOME}/.openclaw"
BACKUP_DIR="${HOME}/.openclaw-backup-$(date +%Y%m%d-%H%M%S)"
BUILD_DIR="'"$BUILD_DIR"'"

echo "========================================"
echo "  Deploy to Production"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}WARNING: This will replace your production OpenClaw!${NC}"
echo "Backup will be created at: $BACKUP_DIR"
echo ""
read -p "Have you tested the build and confirmed it works? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Step 1: Stopping production OpenClaw..."
if pgrep -f "openclaw" > /dev/null 2>&1; then
    pkill -f "openclaw" || true
    sleep 2
fi
echo "✓ Stopped"

echo ""
echo "Step 2: Creating backup..."
mkdir -p "$BACKUP_DIR"
if [ -d "$PROD_DIR/dist" ]; then
    cp -r "$PROD_DIR/dist" "$BACKUP_DIR/"
fi
if [ -d "$PROD_DIR/node_modules" ]; then
    cp -r "$PROD_DIR/node_modules" "$BACKUP_DIR/"
fi
echo "✓ Backup created: $BACKUP_DIR"

echo ""
echo "Step 3: Deploying new build..."
cp -r "$BUILD_DIR/dist" "$PROD_DIR/"
cp -r "$BUILD_DIR/node_modules" "$PROD_DIR/"
echo "✓ Deployed"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To start production OpenClaw:"
echo "  cd $PROD_DIR && npm start"
echo ""
echo "To rollback if needed:"
echo "  ./scripts/rollback-production.sh $BACKUP_DIR"
EOF

chmod +x "$BUILD_DIR/deploy-to-production.sh"
log_info "✓ Deployment script created"

echo ""
echo "========================================"
echo "  Build Complete!"
echo "========================================"
echo ""
echo "Build location: $BUILD_DIR"
echo "Test config: $TEST_CONFIG_DIR"
echo "Test port: $TEST_PORT"
echo ""
echo "Next steps:"
echo ""
echo "1. START TEST INSTANCE:"
echo "   cd $BUILD_DIR"
echo "   ./test-launch.sh"
echo ""
echo "2. IN ANOTHER TERMINAL, VALIDATE:"
echo "   cd $BUILD_DIR"
echo "   ./validate.sh"
echo ""
echo "3. TEST YOUR CUSTOM FEATURES:"
echo "   - Kimi thinking mode"
echo "   - Plugin hooks"
echo "   - apiId mapping"
echo ""
echo "4. IF TESTS PASS, DEPLOY:"
echo "   ./deploy-to-production.sh"
echo ""
echo "5. TO CLEANUP TEST INSTANCE:"
echo "   pkill -f 'test-launch.sh'"
echo "   rm -rf $TEST_DIR"
echo ""
