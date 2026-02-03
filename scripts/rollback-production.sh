#!/bin/bash
# rollback-production.sh - Rollback to previous version
# Usage: ./scripts/rollback-production.sh [backup-directory]

set -euo pipefail

PROD_DIR="${HOME}/.openclaw"

echo "========================================"
echo "  OpenClaw Production Rollback"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Find available backups
if [ $# -eq 0 ]; then
    echo "Available backups:"
    ls -1td ${HOME}/.openclaw-backup-* 2>/dev/null | head -10 | nl
    echo ""
    echo "Usage: $0 <backup-directory>"
    exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}Error: Backup directory not found: $BACKUP_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will rollback production OpenClaw!${NC}"
echo "Backup to restore: $BACKUP_DIR"
echo ""
read -p "Type 'ROLLBACK' to confirm: " CONFIRM

if [ "$CONFIRM" != "ROLLBACK" ]; then
    echo "Rollback cancelled"
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
echo "Step 2: Creating emergency save of current state..."
EMERGENCY_DIR="${HOME}/.openclaw-emergency-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EMERGENCY_DIR"
if [ -d "$PROD_DIR/dist" ]; then
    cp -r "$PROD_DIR/dist" "$EMERGENCY_DIR/" 2>/dev/null || true
fi
echo "✓ Emergency save: $EMERGENCY_DIR"

echo ""
echo "Step 3: Restoring from backup..."
if [ -d "$BACKUP_DIR/dist" ]; then
    rm -rf "$PROD_DIR/dist"
    cp -r "$BACKUP_DIR/dist" "$PROD_DIR/"
fi
if [ -d "$BACKUP_DIR/node_modules" ]; then
    rm -rf "$PROD_DIR/node_modules"
    cp -r "$BACKUP_DIR/node_modules" "$PROD_DIR/"
fi
echo "✓ Restored"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Rollback Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Restored from: $BACKUP_DIR"
echo "Emergency save: $EMERGENCY_DIR"
echo ""
echo "To start production OpenClaw:"
echo "  cd $PROD_DIR && npm start"
echo ""
echo "To undo this rollback:"
echo "  $0 $EMERGENCY_DIR"
