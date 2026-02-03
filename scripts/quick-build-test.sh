#!/bin/bash
# quick-build-test.sh - Fast in-place build with isolated config
# Usage: ./scripts/quick-build-test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_CONFIG_DIR="${HOME}/.openclaw-test-config"
TEST_PORT="${TEST_PORT:-3457}"

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
echo "  Quick Build Test (In-Place)"
echo "========================================"
echo ""

# Pre-flight checks
log_step "Step 1: Pre-flight checks..."

if ! git diff-index --quiet HEAD --; then
    log_warn "Uncommitted changes detected"
    git status --short
fi

# Check Node.js
if ! command -v node > /dev/null 2>&1; then
    log_error "Node.js not found"
    exit 1
fi
log_info "✓ Node.js: $(node --version)"

# Step 2: Build
log_step "Step 2: Building OpenClaw..."
cd "$REPO_ROOT"

log_info "Installing dependencies..."
if command -v pnpm > /dev/null 2>&1; then
    pnpm install > /tmp/npm-install.log 2>&1 || {
        log_error "pnpm install failed"
        tail -20 /tmp/npm-install.log
        exit 1
    }
elif [ -f "package-lock.json" ]; then
    npm ci > /tmp/npm-install.log 2>&1 || {
        log_error "npm ci failed"
        tail -20 /tmp/npm-install.log
        exit 1
    }
else
    npm install > /tmp/npm-install.log 2>&1 || {
        log_error "npm install failed"
        tail -20 /tmp/npm-install.log
        exit 1
    }
fi

log_info "Building..."
npm run build > /tmp/npm-build.log 2>&1 || {
    log_error "Build failed"
    tail -20 /tmp/npm-build.log
    exit 1
}

log_info "✓ Build complete"

# Step 3: Setup test config
log_step "Step 3: Setting up test configuration..."

mkdir -p "$TEST_CONFIG_DIR"

# Copy production config if exists
if [ -d "${HOME}/.openclaw/config" ]; then
    cp -r "${HOME}/.openclaw/config"/* "$TEST_CONFIG_DIR/" 2>/dev/null || true
    log_info "✓ Copied production config"
fi

# Create test overrides
cat > "$TEST_CONFIG_DIR/test-overrides.yaml" << EOF
server:
  port: $TEST_PORT
logLevel: debug
EOF

log_info "✓ Test config ready at: $TEST_CONFIG_DIR"

# Step 4: Create test launcher
log_step "Step 4: Creating test launcher..."

cat > /tmp/test-openclaw-launch.sh << EOF
#!/bin/bash
export OPENCLAW_CONFIG_DIR="$TEST_CONFIG_DIR"
export OPENCLAW_DATA_DIR="${HOME}/.openclaw-test-data"
export PORT="$TEST_PORT"
export NODE_ENV="development"

echo "========================================"
echo "  OpenClaw Test Instance"
echo "========================================"
echo "Config: \$OPENCLAW_CONFIG_DIR"
echo "Port: \$PORT"
echo "PID: \$$"
echo "========================================"
echo ""

cd "$REPO_ROOT"
exec node dist/index.js
EOF

chmod +x /tmp/test-openclaw-launch.sh

# Step 5: Start test instance
log_step "Step 5: Starting test instance..."

/tmp/test-openclaw-launch.sh > /tmp/test-openclaw.log 2>&1 &
echo $! > /tmp/test-openclaw.pid
TEST_PID=$(cat /tmp/test-openclaw.pid)

log_info "Test instance started (PID: $TEST_PID)"
log_info "Waiting for startup..."

# Wait for startup
for i in {1..30}; do
    if curl -s http://localhost:$TEST_PORT/health > /dev/null 2&&1; then
        break
    fi
    sleep 1
done

# Step 6: Validate
log_step "Step 6: Validating..."

if ! ps -p $TEST_PID > /dev/null 2&&1; then
    log_error "Test instance crashed!"
    tail -50 /tmp/test-openclaw.log
    exit 1
fi

if ! curl -s http://localhost:$TEST_PORT/health > /dev/null 2&&1; then
    log_error "Health check failed!"
    tail -50 /tmp/test-openclaw.log
    kill $TEST_PID 2>/dev/null || true
    exit 1
fi

log_info "✓ Health check passed"

# Step 7: Check custom features
log_step "Step 7: Checking custom features..."

# Check logs for custom features
if grep -q "thinking" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Kimi thinking mode detected"
fi

if grep -q "plugin" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Plugin system detected"
fi

if grep -q "apiId" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ apiId mapping detected"
fi

# Step 8: Summary
echo ""
echo "========================================"
echo "  ✅ Test Instance Ready!"
echo "========================================"
echo ""
echo "URL: http://localhost:$TEST_PORT"
echo "Logs: tail -f /tmp/test-openclaw.log"
echo "PID: $TEST_PID"
echo ""
echo "Test your custom features, then:"
echo ""
echo "1) Deploy to production:"
echo "   kill $TEST_PID"
echo "   ./scripts/deploy-production.sh"
echo ""
echo "2) Stop test:"
echo "   kill $TEST_PID"
echo ""
