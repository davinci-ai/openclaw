#!/bin/bash
# sync-upstream.sh - Daily upstream sync with safety checks
# Usage: ./scripts/sync-upstream.sh [--auto]

set -euo pipefail

# Configuration
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"
ORIGIN_REMOTE="origin"
LOG_FILE="${LOG_FILE:-/tmp/openclaw-sync.log}"
AUTO_MODE=false

# Parse arguments
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

# Get current timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DATE=$(date +%Y-%m-%d)

log_info "=== OpenClaw Upstream Sync - $DATE ==="
log_info "Auto mode: $AUTO_MODE"
echo "" | tee -a "$LOG_FILE"

# Safety check: Ensure we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository!"
    exit 1
fi

# Safety check: Ensure no uncommitted changes
if ! git diff-index --quiet HEAD --; then
    log_error "You have uncommitted changes. Commit or stash them first."
    git status --short
    exit 1
fi

# Safety check: Ensure upstream remote exists
if ! git remote | grep -q "^upstream$"; then
    log_error "Upstream remote not found. Run ./scripts/setup-fork.sh first."
    exit 1
fi

# Step 1: Fetch upstream
log_step "1/7: Fetching from upstream..."
if ! git fetch "$UPSTREAM_REMOTE"; then
    log_error "Failed to fetch from upstream"
    exit 1
fi
log_info "✓ Fetched upstream"

# Step 2: Check if there are new changes
log_step "2/7: Checking for new upstream changes..."
UPSTREAM_HEAD=$(git rev-parse upstream/main)
PRISTINE_HEAD=$(git rev-parse pristine-upstream 2>/dev/null || echo "")

if [ "$UPSTREAM_HEAD" = "$PRISTINE_HEAD" ]; then
    log_info "✓ Already up to date with upstream. Nothing to do."
    exit 0
fi

NEW_COMMITS=$(git rev-list --count pristine-upstream..upstream/main 2>/dev/null || echo "0")
log_info "Found $NEW_COMMITS new upstream commit(s)"
echo ""
echo "Recent upstream commits:"
git log --oneline --color=always pristine-upstream..upstream/main | head -10
echo ""

# In manual mode, ask for confirmation
if [ "$AUTO_MODE" = false ]; then
    read -p "Proceed with sync? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Sync cancelled by user"
        exit 0
    fi
fi

# Step 3: Create backup tags
log_step "3/7: Creating backup tags..."
BACKUP_TAG="backup/before-sync-$TIMESTAMP"
git tag "$BACKUP_TAG"
log_info "✓ Created backup tag: $BACKUP_TAG"

# Step 4: Update pristine-upstream branch
log_step "4/7: Updating pristine-upstream branch..."
git checkout pristine-upstream

# Try fast-forward first
if git merge --ff-only upstream/main 2>/dev/null; then
    log_info "✓ Fast-forwarded pristine-upstream to upstream/main"
else
    # If fast-forward fails, reset to upstream (shouldn't happen with proper workflow)
    log_warn "Could not fast-forward, resetting pristine-upstream..."
    git reset --hard upstream/main
    log_info "✓ Reset pristine-upstream to upstream/main"
fi

# Push pristine-upstream
git push "$ORIGIN_REMOTE" pristine-upstream
log_info "✓ Pushed pristine-upstream to origin"

# Step 5: Merge to staging
log_step "5/7: Merging to staging branch..."
git checkout staging

# Create backup tag for staging
BACKUP_TAG_STAGING="backup/staging-before-sync-$TIMESTAMP"
git tag "$BACKUP_TAG_STAGING"

if git merge pristine-upstream --no-ff -m "Sync: Merge upstream changes ($DATE)

Upstream commits: $NEW_COMMITS
Backup tag: $BACKUP_TAG"; then
    log_info "✓ Merged upstream into staging"
else
    log_error "Merge conflicts detected in staging!"
    log_error "Please resolve conflicts manually:"
    log_error "  1. Resolve conflicts in the listed files"
    log_error "  2. git add <resolved-files>"
    log_error "  3. git merge --continue"
    log_error "  4. Run this script again"
    log_error ""
    log_error "To abort and restore:"
    log_error "  git merge --abort"
    log_error "  git reset --hard $BACKUP_TAG_STAGING"
    
    # Show conflicting files
    echo ""
    echo "Conflicting files:"
    git diff --name-only --diff-filter=U
    
    exit 1
fi

# Push staging
git push "$ORIGIN_REMOTE" staging
log_info "✓ Pushed staging to origin"

# Step 6: Run tests
log_step "6/7: Running tests..."

TEST_FAILED=false

# Check for test suite
if [ -f "package.json" ] && grep -q "\"test\"" package.json 2>/dev/null; then
    log_info "Running npm test..."
    if npm test 2>&1 | tee -a "$LOG_FILE"; then
        log_info "✓ Tests passed"
    else
        log_error "✗ Tests failed!"
        TEST_FAILED=true
    fi
elif [ -f "Makefile" ] && grep -q "test" Makefile 2>/dev/null; then
    log_info "Running make test..."
    if make test 2>&1 | tee -a "$LOG_FILE"; then
        log_info "✓ Tests passed"
    else
        log_error "✗ Tests failed!"
        TEST_FAILED=true
    fi
elif [ -d "tests" ] || [ -d "test" ]; then
    log_warn "Test directory exists but no automated test runner configured"
    log_warn "Please run tests manually before promoting to custom/main"
else
    log_warn "No test suite detected"
fi

if [ "$TEST_FAILED" = true ]; then
    log_error "Tests failed on staging branch!"
    log_error "Fix issues before promoting to custom/main"
    log_error ""
    log_error "To rollback staging:"
    log_error "  git reset --hard $BACKUP_TAG_STAGING"
    log_error "  git push --force-with-lease origin staging"
    exit 1
fi

# Step 7: Promote to custom/main
log_step "7/7: Promoting to custom/main..."

if [ "$AUTO_MODE" = true ]; then
    # In auto mode, only promote if tests passed
    log_info "Auto-promoting staging to custom/main..."
    git checkout custom/main
    
    BACKUP_TAG_CUSTOM="backup/custom-before-sync-$TIMESTAMP"
    git tag "$BACKUP_TAG_CUSTOM"
    
    git merge staging --no-ff -m "Promote: Staging to custom/main ($DATE)

Tests passed, promoting staged upstream changes."
    
    git push "$ORIGIN_REMOTE" custom/main
    log_info "✓ Pushed custom/main to origin"
else
    # In manual mode, ask for confirmation
    echo ""
    log_warn "Ready to promote staging → custom/main"
    read -p "Have you reviewed changes and confirmed tests pass? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" == "yes" ]]; then
        git checkout custom/main
        
        BACKUP_TAG_CUSTOM="backup/custom-before-sync-$TIMESTAMP"
        git tag "$BACKUP_TAG_CUSTOM"
        
        git merge staging --no-ff -m "Promote: Staging to custom/main ($DATE)"
        
        git push "$ORIGIN_REMOTE" custom/main
        log_info "✓ Pushed custom/main to origin"
    else
        log_info "Promotion to custom/main skipped. Staging is ready for review."
        log_info "Promote manually later with:"
        log_info "  git checkout custom/main && git merge staging && git push origin custom/main"
    fi
fi

# Push all backup tags
git push "$ORIGIN_REMOTE" --tags

# Summary
echo ""
log_info "=== Sync Complete ==="
echo ""
echo "Summary:"
echo "  - Upstream commits merged: $NEW_COMMITS"
echo "  - pristine-upstream: updated"
echo "  - staging: updated and tested"
if [ "$AUTO_MODE" = true ] || [[ "${CONFIRM:-}" == "yes" ]]; then
    echo "  - custom/main: updated"
else
    echo "  - custom/main: NOT updated (manual promotion needed)"
fi
echo ""
echo "Backup tags created:"
git tag -l "backup/*-$TIMESTAMP" | sed 's/^/  - /'
echo ""
echo "Next steps:"
echo "  - Review changes: git log custom/main --oneline -10"
echo "  - Update CUSTOM_CHANGES.md with any new modifications"
echo ""
