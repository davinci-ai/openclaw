#!/bin/bash
# emergency-rollback.sh - Emergency rollback to a previous state
# Usage: ./scripts/emergency-rollback.sh [backup-tag]

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}=== EMERGENCY ROLLBACK ===${NC}"
echo ""

# Show available backups if no argument provided
if [ $# -eq 0 ]; then
    echo "Available backup tags:"
    git tag -l "backup/*" --sort=-creatordate | head -20 | nl
    echo ""
    echo "Usage: $0 <backup-tag>"
    echo "Example: $0 backup/before-sync-20240203-120000"
    exit 1
fi

BACKUP_TAG=$1

# Verify backup tag exists
if ! git rev-parse "$BACKUP_TAG" >/dev/null 2>&1; then
    echo -e "${RED}Error: Backup tag '$BACKUP_TAG' not found${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will reset branches to the backup state${NC}"
echo "Backup tag: $BACKUP_TAG"
echo "Backup date: $(git log -1 --format=%ai "$BACKUP_TAG")"
echo ""
echo "This will affect:"
echo "  - pristine-upstream"
echo "  - staging"
echo "  - custom/main"
echo ""
echo -e "${RED}Any commits made after this backup will be LOST!${NC}"
echo ""

read -p "Type 'ROLLBACK' to confirm: " confirm
if [ "$confirm" != "ROLLBACK" ]; then
    echo "Rollback cancelled"
    exit 0
fi

echo ""
echo "Creating emergency save point..."
EMERGENCY_TAG="emergency/pre-rollback-$(date +%Y%m%d-%H%M%S)"
git tag "$EMERGENCY_TAG"
echo "Emergency tag created: $EMERGENCY_TAG"

echo ""
echo "Rolling back branches..."

# Determine which branch the backup was for
BACKUP_NAME=$(echo "$BACKUP_TAG" | sed 's/backup\/before-sync-//' | sed 's/backup\///')

# Rollback pristine-upstream
git checkout pristine-upstream
git reset --hard "$BACKUP_TAG"
git push --force-with-lease origin pristine-upstream
echo -e "${GREEN}✓${NC} pristine-upstream rolled back"

# Rollback staging
git checkout staging
git reset --hard "$BACKUP_TAG"
git push --force-with-lease origin staging
echo -e "${GREEN}✓${NC} staging rolled back"

# Rollback custom/main
git checkout custom/main
git reset --hard "$BACKUP_TAG"
git push --force-with-lease origin custom/main
echo -e "${GREEN}✓${NC} custom/main rolled back"

echo ""
echo -e "${GREEN}=== Rollback Complete ===${NC}"
echo ""
echo "Emergency save point: $EMERGENCY_TAG"
echo ""
echo "If you need to undo this rollback:"
echo "  git checkout custom/main"
echo "  git reset --hard $EMERGENCY_TAG"
echo "  git push --force-with-lease origin custom/main"
