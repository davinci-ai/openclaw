#!/bin/bash
# health-check.sh - Verify fork health and sync status

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

echo "=== OpenClaw Fork Health Check ==="
echo ""

# Check 1: Remote configuration
echo "Checking remotes..."
if git remote | grep -q "^upstream$"; then
    UPSTREAM_URL=$(git remote get-url upstream)
    if echo "$UPSTREAM_URL" | grep -q "openclaw/openclaw"; then
        check_pass "Upstream remote configured correctly"
    else
        check_warn "Upstream remote exists but points to: $UPSTREAM_URL"
    fi
else
    check_fail "Upstream remote not found"
fi

if git remote | grep -q "^origin$"; then
    check_pass "Origin remote configured"
else
    check_fail "Origin remote not found"
fi

# Check 2: Branch existence
echo ""
echo "Checking branches..."
for branch in pristine-upstream staging custom/main; do
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        check_pass "Branch exists: $branch"
    else
        check_fail "Branch missing: $branch"
    fi
done

# Check 3: Sync status
echo ""
echo "Checking sync status..."
git fetch upstream 2>/dev/null || true

if git show-ref --verify --quiet refs/heads/pristine-upstream; then
    UPSTREAM_HEAD=$(git rev-parse upstream/main 2>/dev/null || echo "")
    PRISTINE_HEAD=$(git rev-parse pristine-upstream 2>/dev/null || echo "")
    
    if [ -n "$UPSTREAM_HEAD" ] && [ -n "$PRISTINE_HEAD" ]; then
        BEHIND=$(git rev-list --count "pristine-upstream..upstream/main" 2>/dev/null || echo "0")
        
        if [ "$BEHIND" -eq 0 ]; then
            check_pass "pristine-upstream is up to date"
        elif [ "$BEHIND" -lt 5 ]; then
            check_warn "pristine-upstream is $BEHIND commits behind upstream"
        else
            check_fail "pristine-upstream is $BEHIND commits behind upstream (sync needed!)"
        fi
    fi
fi

# Check 4: Staging vs pristine-upstream
if git show-ref --verify --quiet refs/heads/staging && \
   git show-ref --verify --quiet refs/heads/pristine-upstream; then
    STAGING_BEHIND=$(git rev-list --count "staging..pristine-upstream" 2>/dev/null || echo "0")
    
    if [ "$STAGING_BEHIND" -eq 0 ]; then
        check_pass "staging is current with pristine-upstream"
    else
        check_warn "staging is $STAGING_BEHIND commits behind pristine-upstream"
    fi
fi

# Check 5: custom/main vs staging
if git show-ref --verify --quiet refs/heads/custom/main && \
   git show-ref --verify --quiet refs/heads/staging; then
    CUSTOM_BEHIND=$(git rev-list --count "custom/main..staging" 2>/dev/null || echo "0")
    
    if [ "$CUSTOM_BEHIND" -eq 0 ]; then
        check_pass "custom/main is current with staging"
    else
        check_warn "custom/main is $CUSTOM_BEHIND commits behind staging (promotion needed)"
    fi
fi

# Check 6: Backup tags
echo ""
echo "Checking backups..."
BACKUP_COUNT=$(git tag -l "backup/*" | wc -l)
if [ "$BACKUP_COUNT" -eq 0 ]; then
    check_warn "No backup tags found"
elif [ "$BACKUP_COUNT" -lt 5 ]; then
    check_pass "Found $BACKUP_COUNT backup tag(s)"
else
    check_pass "Found $BACKUP_COUNT backup tags"
    
    # Check for old backups
    OLD_BACKUPS=$(git tag -l "backup/*" --sort=creatordate | head -n -30 | wc -l)
    if [ "$OLD_BACKUPS" -gt 0 ]; then
        check_warn "$OLD_BACKUPS old backup tags (consider cleanup)"
    fi
fi

# Check 7: Protected files
echo ""
echo "Checking protected files..."
if [ -f ".sync-protected" ]; then
    check_pass ".sync-protected file exists"
    
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        [[ "$pattern" =~ ^#.*$ ]] && continue
        [ -z "$pattern" ] && continue
        
        if [[ "$pattern" == */ ]]; then
            if [ -d "$pattern" ]; then
                check_pass "Protected directory exists: $pattern"
            else
                check_fail "Protected directory missing: $pattern"
            fi
        else
            if [ -e "$pattern" ]; then
                check_pass "Protected file exists: $pattern"
            else
                check_warn "Protected file not found: $pattern"
            fi
        fi
    done < .sync-protected
else
    check_warn ".sync-protected file not found"
fi

# Check 8: Documentation
echo ""
echo "Checking documentation..."
if [ -f "CUSTOM_CHANGES.md" ]; then
    check_pass "CUSTOM_CHANGES.md exists"
else
    check_warn "CUSTOM_CHANGES.md not found"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found${NC}"
    exit 1
fi
