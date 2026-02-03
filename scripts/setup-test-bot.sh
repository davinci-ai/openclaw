#!/bin/bash
# setup-test-bot.sh - Configure test Telegram bot for OpenClaw testing
# Usage: ./scripts/setup-test-bot.sh

set -euo pipefail

TEST_CONFIG_DIR="${HOME}/.openclaw-test-config"

echo "========================================"
echo "  Test Bot Setup"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if test instance is running
if ! ps aux | grep -v grep | grep -q "test-openclaw-launch.sh"; then
    log_warn "Test instance not running!"
    echo "Start it first with: ./scripts/quick-build-test.sh"
    exit 1
fi

log_info "✓ Test instance detected"

# Step 1: Get bot token
echo ""
log_step "Step 1: Telegram Bot Token"
echo ""
echo "To create a test bot:"
echo "  1. Open Telegram"
echo "  2. Message @BotFather"
echo "  3. Send /newbot"
echo "  4. Follow instructions"
echo "  5. Copy the bot token"
echo ""
read -p "Enter your test bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    echo "No token provided, exiting"
    exit 1
fi

# Step 2: Get Parakeet API key
echo ""
log_step "Step 2: Parakeet Voice Service"
echo ""
echo "For voice testing, you need Parakeet API key:"
echo "  1. Visit https://parakeet.ai"
echo "  2. Sign up / Log in"
echo "  3. Get API key from dashboard"
echo ""
read -p "Enter Parakeet API key (or press Enter to skip voice): " PARAKEET_KEY

# Step 3: Update config
echo ""
log_step "Step 3: Updating configuration..."

# Update the config file with actual values
sed -i.bak "s/\${TEST_TELEGRAM_BOT_TOKEN}/$BOT_TOKEN/g" "$TEST_CONFIG_DIR/config.yaml"

if [ -n "$PARAKEET_KEY" ]; then
    sed -i.bak "s/\${PARAKEET_API_KEY}/$PARAKEET_KEY/g" "$TEST_CONFIG_DIR/config.yaml"
    log_info "✓ Parakeet voice configured"
else
    # Disable voice if no key
    sed -i.bak 's/enabled: true/enabled: false/g' "$TEST_CONFIG_DIR/config.yaml"
    log_warn "Voice disabled (no API key)"
fi

rm -f "$TEST_CONFIG_DIR/config.yaml.bak"

# Step 4: Restart test instance
echo ""
log_step "Step 4: Restarting test instance..."

# Find and kill test instance
TEST_PID=$(ps aux | grep "test-openclaw-launch.sh" | grep -v grep | awk '{print $2}')
if [ -n "$TEST_PID" ]; then
    kill $TEST_PID 2>/dev/null || true
    sleep 2
fi

# Start fresh
/tmp/test-openclaw-launch.sh > /tmp/test-openclaw.log 2>&1 &
echo $! > /tmp/test-openclaw.pid
NEW_PID=$(cat /tmp/test-openclaw.pid)

log_info "Test instance restarted (PID: $NEW_PID)"
log_info "Waiting for startup..."

# Wait for startup
for i in {1..30}; do
    if curl -s http://localhost:3457/health > /dev/null 2&&1; then
        break
    fi
    sleep 1
done

# Step 5: Verify
echo ""
log_step "Step 5: Verification..."

if curl -s http://localhost:3457/health > /dev/null 2&&1; then
    log_info "✓ Test instance is healthy"
else
    log_warn "Health check failed, check logs:"
    tail -20 /tmp/test-openclaw.log
fi

# Check Telegram connection
if grep -q "telegram" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Telegram bot connecting..."
fi

echo ""
echo "========================================"
echo "  ✅ Test Bot Setup Complete!"
echo "========================================"
echo ""
echo "Test bot is ready!"
echo ""
echo "To test:"
echo "  1. Open Telegram"
echo "  2. Find your test bot"
echo "  3. Send a message"
echo "  4. Try voice messages (if Parakeet configured)"
echo ""
echo "Monitor logs:"
echo "  tail -f /tmp/test-openclaw.log"
echo ""
echo "Test URL: http://localhost:3457"
echo ""
