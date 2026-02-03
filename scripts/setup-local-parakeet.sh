#!/bin/bash
# setup-local-parakeet.sh - Configure test instance to use local Parakeet service
# Usage: ./scripts/setup-local-parakeet.sh

set -euo pipefail

TEST_CONFIG_DIR="${HOME}/.openclaw-test-config"

echo "========================================"
echo "  Local Parakeet Setup"
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

# Check if local Parakeet is running
log_step "Checking local Parakeet service..."

if curl -s http://localhost:8095/v1/audio/transcriptions > /dev/null 2&&1 || \
   curl -s http://host.docker.internal:8095/v1/audio/transcriptions > /dev/null 2&&1; then
    log_info "✓ Local Parakeet service detected"
else
    log_warn "Local Parakeet not responding on localhost:8095"
    log_warn "Make sure Parakeet is running before testing"
fi

# Step 1: Get bot token
echo ""
log_step "Step 1: Telegram Bot Token"
echo ""
echo "Get your bot token from @BotFather:"
echo "  1. Open Telegram"
echo "  2. Message @BotFather"
echo "  3. Send /token"
echo "  4. Select your test bot"
echo "  5. Copy the token"
echo ""
read -p "Enter your test bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    echo "No token provided, exiting"
    exit 1
fi

# Step 2: Create config with local Parakeet
echo ""
log_step "Step 2: Creating test configuration..."

mkdir -p "$TEST_CONFIG_DIR"

cat > "$TEST_CONFIG_DIR/config.yaml" << EOF
# OpenClaw Test Configuration
# Uses LOCAL Parakeet service on Mac mini

server:
  port: 3457

# Telegram Bot (TEST)
telegram:
  enabled: true
  botToken: "$BOT_TOKEN"
  # Allow all users for testing
  allowedUsers: []

# Voice Services - Using LOCAL ParakeET
voice:
  enabled: true
  
  # Text-to-Speech (TTS)
  tts:
    enabled: true
    provider: parakeet
    parakeet:
      # Connect to local Parakeet on Mac mini
      baseUrl: "http://host.docker.internal:8095"
      apiKey: "local"  # Not needed for local service
      timeoutMs: 30000
  
  # Speech-to-Text (STT)  
  stt:
    enabled: true
    provider: parakeet
    parakeet:
      # Connect to local Parakeet on Mac mini
      baseUrl: "http://host.docker.internal:8095"
      apiKey: "local"
      timeoutMs: 30000
      language: "en"

# AI Models
agents:
  defaults:
    model: "kimi-coding/k2p5"
    extraParams:
      # Enable thinking mode
      thinking:
        enabled: true
        budget: 4096

# Plugins
plugins:
  enabled: true
  directories:
    - "./plugins"

# Logging
logLevel: debug
EOF

log_info "✓ Test config created with local Parakeet"

# Step 3: Restart test instance
echo ""
log_step "Step 3: Restarting test instance..."

# Find and kill existing test instance
TEST_PID=$(ps aux | grep "test-openclaw-launch.sh" | grep -v grep | awk '{print $2}' || true)
if [ -n "$TEST_PID" ]; then
    log_info "Stopping existing test instance..."
    kill $TEST_PID 2>/dev/null || true
    sleep 3
fi

# Create launcher script
cat > /tmp/test-openclaw-launch.sh << EOF
#!/bin/bash
export OPENCLAW_CONFIG_DIR="$TEST_CONFIG_DIR"
export OPENCLAW_DATA_DIR="${HOME}/.openclaw-test-data"
export PORT="3457"
export NODE_ENV="development"

echo "========================================"
echo "  OpenClaw Test Instance"
echo "========================================"
echo "Config: \$OPENCLAW_CONFIG_DIR"
echo "Port: \$PORT"
echo "Parakeet: http://host.docker.internal:8095"
echo "PID: \$$"
echo "========================================"
echo ""

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec node dist/index.js
EOF

chmod +x /tmp/test-openclaw-launch.sh

# Start test instance
/tmp/test-openclaw-launch.sh > /tmp/test-openclaw.log 2>&1 &
echo $! > /tmp/test-openclaw.pid
NEW_PID=$(cat /tmp/test-openclaw.pid)

log_info "Test instance started (PID: $NEW_PID)"
log_info "Waiting for startup..."

# Wait for startup
for i in {1..30}; do
    if curl -s http://localhost:3457/health > /dev/null 2&&1; then
        break
    fi
    sleep 1
done

# Step 4: Verify
echo ""
log_step "Step 4: Verification..."

if curl -s http://localhost:3457/health > /dev/null 2&&1; then
    log_info "✓ Test instance is healthy"
else
    log_warn "Health check failed, check logs:"
    tail -20 /tmp/test-openclaw.log
fi

if grep -q "telegram" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Telegram bot connecting..."
fi

if grep -q "parakeet\|voice" /tmp/test-openclaw.log 2>/dev/null; then
    log_info "✓ Voice services initializing..."
fi

echo ""
echo "========================================"
echo "  ✅ Test Setup Complete!"
echo "========================================"
echo ""
echo "Test bot is ready with LOCAL Parakeet!"
echo ""
echo "Configuration:"
echo "  - Telegram Bot: Your test bot"
echo "  - Parakeet TTS: http://host.docker.internal:8095"
echo "  - Parakeet STT: http://host.docker.internal:8095"
echo "  - Port: 3457"
echo ""
echo "To test:"
echo "  1. Open Telegram"
echo "  2. Message your test bot"
echo "  3. Send voice messages - they'll use local Parakeet!"
echo ""
echo "Monitor logs:"
echo "  tail -f /tmp/test-openclaw.log"
echo ""
echo "Test URL: http://localhost:3457"
echo ""
