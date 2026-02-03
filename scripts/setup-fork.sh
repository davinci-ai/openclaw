#!/bin/bash
# setup-fork.sh - Initial setup for OpenClaw fork sync strategy
# Run this once to configure the branch structure

set -e

echo "=== OpenClaw Fork Setup ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right repo
if ! git remote -v | grep -q "openclaw"; then
    log_error "This doesn't appear to be an OpenClaw repository"
    exit 1
fi

# Ensure working directory is clean
if ! git diff-index --quiet HEAD --; then
    log_error "Working directory has uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

# Add upstream remote if not exists
if ! git remote | grep -q "upstream"; then
    log_info "Adding upstream remote..."
    git remote add upstream https://github.com/openclaw/openclaw.git
else
    log_info "Upstream remote already configured"
fi

# Fetch upstream
log_info "Fetching upstream..."
git fetch upstream

# Show current state
echo ""
log_info "Current remotes:"
git remote -v
echo ""

# Create pristine-upstream branch (mirror of upstream/main)
log_info "Creating pristine-upstream branch..."
if git show-ref --verify --quiet refs/heads/pristine-upstream; then
    log_warn "pristine-upstream branch already exists"
else
    git checkout -b pristine-upstream upstream/main
    log_info "Created pristine-upstream branch from upstream/main"
fi

# Create staging branch (integration/testing)
log_info "Creating staging branch..."
if git show-ref --verify --quiet refs/heads/staging; then
    log_warn "staging branch already exists"
else
    git checkout -b staging
    log_info "Created staging branch"
fi

# Create custom/main branch (your production)
log_info "Creating custom/main branch..."
if git show-ref --verify --quiet refs/heads/custom/main; then
    log_warn "custom/main branch already exists"
else
    git checkout -b custom/main
    log_info "Created custom/main branch"
fi

# Return to main and set up tracking
git checkout main

# Push branches to origin
echo ""
log_info "Pushing branches to origin..."
git push -u origin pristine-upstream || log_warn "Could not push pristine-upstream (may already exist)"
git push -u origin staging || log_warn "Could not push staging (may already exist)"
git push -u origin custom/main || log_warn "Could not push custom/main (may already exist)"

# Create .sync-protected file
echo ""
log_info "Creating .sync-protected file..."
cat > .sync-protected << 'EOF'
# Files and directories that should never be overwritten by upstream sync
# These trigger warnings if missing after a merge

# Custom code directories
src/custom/
config/custom/
scripts/custom/

# Custom configuration files
config/production.yaml
config/custom.yaml
.env.local

# Documentation
CUSTOM_CHANGES.md
EOF

# Create CUSTOM_CHANGES.md template
echo ""
log_info "Creating CUSTOM_CHANGES.md..."
cat > CUSTOM_CHANGES.md << 'EOF'
# Custom Modifications to OpenClaw

This document tracks all custom modifications made to this fork.
Update this file whenever you make custom changes.

## Modified Files
<!-- List files you've modified from upstream -->
- 

## Added Files/Directories
<!-- List new files/directories you've added -->
- 

## Removed/Disabled Features
<!-- List anything you've removed or disabled -->
- 

## Configuration Changes
<!-- List configuration modifications -->
- 

## Last Upstream Sync
<!-- Update this after each sync -->
- Date: 
- Upstream Commit: 
- Conflicts Resolved: 
EOF

# Add and commit documentation
git add .sync-protected CUSTOM_CHANGES.md
git commit -m "Add fork sync documentation and protected files list" || log_warn "Nothing to commit"
git push origin main

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Branch structure:"
echo "  pristine-upstream  - Mirror of upstream/main (never modify directly)"
echo "  staging            - Integration/testing branch"
echo "  custom/main        - Your production branch with custom changes"
echo "  main               - Your original branch (keep or deprecate)"
echo ""
echo "Next steps:"
echo "  1. Review and update CUSTOM_CHANGES.md with your modifications"
echo "  2. Update .sync-protected with critical custom files"
echo "  3. Run ./scripts/sync-upstream.sh to test the sync process"
echo "  4. Set up GitHub Actions for automated daily syncs"
echo ""
