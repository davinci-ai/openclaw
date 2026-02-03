#!/bin/bash
# resolve-conflicts.sh - Interactive conflict resolution helper
# Run this when merge conflicts occur

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== OpenClaw Conflict Resolution ===${NC}"
echo ""

# Check if we're in a merge conflict state
if ! git diff --name-only --diff-filter=U | grep -q .; then
    echo -e "${GREEN}No merge conflicts detected!${NC}"
    exit 0
fi

# Show summary
echo "Conflicting files:"
git diff --name-only --diff-filter=U | nl
echo ""

# Process each conflicting file
for file in $(git diff --name-only --diff-filter=U); do
    echo "========================================"
    echo -e "${YELLOW}File: $file${NC}"
    echo ""
    
    # Show conflict summary
    OUR_CHANGES=$(grep -c "<<<<<<<" "$file" 2>/dev/null || echo 0)
    echo "Conflict sections: $OUR_CHANGES"
    echo ""
    
    # Show last commit info for each branch
    echo "Last modified in current branch:"
    git log -1 --format="  %h - %s (%an, %ar)" HEAD -- "$file" 2>/dev/null || echo "  (not in current branch)"
    
    echo "Last modified in upstream:"
    git log -1 --format="  %h - %s (%an, %ar)" pristine-upstream -- "$file" 2>/dev/null || echo "  (not in upstream)"
    
    # Check if it's a protected file
    if [ -f ".sync-protected" ] && grep -q "$file" .sync-protected 2>/dev/null; then
        echo ""
        echo -e "${RED}⚠️  WARNING: This is a PROTECTED file!${NC}"
        echo "Listed in .sync-protected"
    fi
    
    echo ""
    echo "Options:"
    echo "  1. Keep OUR changes (custom)"
    echo "  2. Accept THEIRS changes (upstream)"
    echo "  3. Manual edit (opens editor)"
    echo "  4. Show diff"
    echo "  5. Skip for now"
    echo "  6. Abort merge"
    echo ""
    
    read -p "Choose action (1-6): " choice
    
    case $choice in
        1)
            git checkout --ours "$file"
            git add "$file"
            echo -e "${GREEN}✓ Kept our changes for $file${NC}"
            ;;
        2)
            git checkout --theirs "$file"
            git add "$file"
            echo -e "${GREEN}✓ Accepted upstream changes for $file${NC}"
            ;;
        3)
            ${EDITOR:-vi} "$file"
            if grep -q "<<<<<<<" "$file"; then
                echo -e "${YELLOW}⚠️  Conflict markers still present in $file${NC}"
                read -p "Mark as resolved anyway? (y/N): " force
                if [[ $force =~ ^[Yy]$ ]]; then
                    git add "$file"
                    echo -e "${GREEN}✓ Marked $file as resolved${NC}"
                fi
            else
                git add "$file"
                echo -e "${GREEN}✓ Manual edit completed for $file${NC}"
            fi
            ;;
        4)
            git diff "$file" | head -50
            echo ""
            read -p "Press Enter to continue..."
            # Re-process this file
            continue
            ;;
        5)
            echo -e "${YELLOW}Skipped $file${NC}"
            ;;
        6)
            git merge --abort
            echo -e "${RED}✗ Merge aborted${NC}"
            exit 1
            ;;
        *)
            echo -e "${YELLOW}Invalid choice, skipping...${NC}"
            ;;
    esac
    echo ""
done

# Check if all conflicts are resolved
if git diff --name-only --diff-filter=U | grep -q .; then
    echo -e "${YELLOW}Some conflicts remain unresolved!${NC}"
    echo "Unresolved files:"
    git diff --name-only --diff-filter=U
    exit 1
else
    echo -e "${GREEN}✓ All conflicts resolved!${NC}"
    echo ""
    read -p "Complete the merge commit? (Y/n): " complete
    if [[ ! $complete =~ ^[Nn]$ ]]; then
        git merge --continue
        echo -e "${GREEN}✓ Merge completed${NC}"
    else
        echo "Merge commit ready. Complete manually with: git merge --continue"
    fi
fi
