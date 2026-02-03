# OpenClaw Fork Sync Strategy

This repository uses a multi-branch workflow to stay synchronized with upstream OpenClaw while preserving custom modifications.

## Branch Structure

| Branch | Purpose | Notes |
|--------|---------|-------|
| `upstream/main` | Original OpenClaw repository | Read-only reference |
| `pristine-upstream` | Mirror of upstream/main | Never modify directly |
| `staging` | Integration & testing | Merge conflicts resolved here |
| `custom/main` | Your production branch | Custom changes + tested upstream |

## Quick Start

### 1. Initial Setup (Run Once)

```bash
./scripts/setup-fork.sh
```

This sets up:
- Upstream remote pointing to `openclaw/openclaw`
- Branch structure (`pristine-upstream`, `staging`, `custom/main`)
- Protected files list (`.sync-protected`)
- Custom changes documentation (`CUSTOM_CHANGES.md`)

### 2. Daily Sync (Manual)

```bash
./scripts/sync-upstream.sh
```

This will:
1. Fetch latest upstream changes
2. Create backup tags
3. Update `pristine-upstream`
4. Merge to `staging`
5. Run tests
6. Ask for confirmation before promoting to `custom/main`

### 3. Daily Sync (Automated)

GitHub Actions runs daily at 6 AM UTC. It will:
- Automatically sync upstream → pristine-upstream → staging
- Run tests
- Create an issue if conflicts occur
- Optionally auto-promote to `custom/main` (if tests pass)

## Conflict Resolution

If merge conflicts occur:

```bash
./scripts/resolve-conflicts.sh
```

This interactive script helps you:
- See conflicting files
- Choose resolution strategy (keep ours/theirs, manual edit)
- Complete the merge

## Health Check

Verify your fork is properly configured:

```bash
./scripts/health-check.sh
```

Checks:
- Remote configuration
- Branch structure
- Sync status (how far behind upstream)
- Backup tags
- Protected files

## Emergency Rollback

If something goes wrong:

```bash
# List available backups
./scripts/emergency-rollback.sh

# Rollback to specific backup
./scripts/emergency-rollback.sh backup/before-sync-20240203-120000
```

## Important Files

| File | Purpose |
|------|---------|
| `.sync-protected` | List of files/directories that should never be overwritten |
| `CUSTOM_CHANGES.md` | Document your custom modifications |
| `scripts/setup-fork.sh` | Initial setup script |
| `scripts/sync-upstream.sh` | Daily sync script |
| `scripts/resolve-conflicts.sh` | Interactive conflict resolution |
| `scripts/health-check.sh` | Verify fork health |
| `scripts/emergency-rollback.sh` | Emergency rollback |
| `.github/workflows/daily-sync.yml` | Automated GitHub Actions workflow |

## Workflow Diagram

```
upstream/main ──► pristine-upstream ──► staging ──► custom/main
                      ↑                    ↑            ↑
                 (mirror)            (testing)    (production)
```

## Best Practices

1. **Always sync daily** - Small, frequent merges are easier than large ones
2. **Never commit to `pristine-upstream`** - It's a clean mirror
3. **Resolve conflicts in `staging`** - Never directly in `custom/main`
4. **Create feature branches** for new custom work: `git checkout -b feature/my-feature custom/main`
5. **Update `CUSTOM_CHANGES.md`** whenever you make modifications
6. **Review upstream changes** before promoting to `custom/main`
7. **Keep custom code isolated** in `src/custom/` when possible

## Troubleshooting

### "Cannot fast-forward pristine-upstream"

This means someone committed directly to `pristine-upstream`. Fix:
```bash
git checkout pristine-upstream
git reset --hard upstream/main
git push --force-with-lease origin pristine-upstream
```

### "Merge conflicts detected"

Run the interactive resolver:
```bash
./scripts/resolve-conflicts.sh
```

### "Tests failed after merge"

1. Fix the issues in `staging`
2. Run tests again
3. Then promote to `custom/main`

Or rollback:
```bash
./scripts/emergency-rollback.sh backup/before-sync-XXXXXX
```

## GitHub Actions

The workflow `.github/workflows/daily-sync.yml`:
- Runs daily at 6 AM UTC
- Can be triggered manually with `workflow_dispatch`
- Creates issues on merge conflicts
- Runs tests automatically
- Can auto-promote to `custom/main` (optional)

## Custom Code Markers

When modifying upstream files, add markers:

```typescript
// === CUSTOM MODIFICATION ===
// Purpose: Enterprise SSO integration
// Added: 2024-01-15
// ===========================

your custom code here

// === END CUSTOM MODIFICATION ===
```

This makes conflicts easier to spot and resolve.
