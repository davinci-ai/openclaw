# Safe Testing & Deployment Guide

This guide explains how to safely build, test, and deploy your custom OpenClaw fork without affecting your production instance.

## Overview

The testing system provides **complete isolation** between test and production:
- **Separate build directory** (`/tmp/openclaw-test-build-*`)
- **Separate config directory** (`~/.openclaw-test/`)
- **Separate port** (3457 by default, vs 3000 for production)
- **Automatic backups** before deployment
- **One-command rollback** if issues occur

## Quick Start

### Option 1: Full Automated Workflow (Recommended)

```bash
./scripts/full-test-and-deploy.sh
```

This will:
1. Build in isolated environment
2. Start test instance
3. Run validation checks
4. Ask for deployment confirmation
5. Deploy to production

### Option 2: Manual Step-by-Step

```bash
# Step 1: Build
./scripts/safe-test-build.sh

# Step 2: Start test instance (in terminal 1)
cd /tmp/openclaw-test-build-XXXXX
./test-launch.sh

# Step 3: Validate (in terminal 2)
./validate.sh

# Step 4: Test your features manually
# ... test Kimi thinking mode, plugins, etc.

# Step 5: Deploy (if tests pass)
./deploy-to-production.sh
```

## Detailed Workflow

### 1. Build Phase

```bash
./scripts/safe-test-build.sh
```

**What it does:**
- Creates isolated build directory in `/tmp/`
- Copies source code
- Installs dependencies (`npm ci`)
- Builds OpenClaw (`npm run build`)
- Creates test launcher script
- Creates validation script
- Creates deployment script

**Output:**
```
Build location: /tmp/openclaw-test-build-12345
Test config: ~/.openclaw-test/config
Test port: 3457
```

### 2. Test Phase

```bash
cd /tmp/openclaw-test-build-XXXXX
./test-launch.sh
```

**What it does:**
- Uses separate config directory (`~/.openclaw-test/`)
- Runs on port 3457 (won't conflict with production on 3000)
- Logs to separate location

**In another terminal:**
```bash
./validate.sh
```

**Checks:**
- Process is running
- Port is listening
- No critical errors in logs
- Health endpoint responding

### 3. Manual Testing

Test your custom features:
- Kimi K2.5 thinking mode
- Plugin hooks (message_sending, before_media_understanding)
- apiId mapping for model variants
- clearAudioMetadata hook

### 4. Deployment Phase

```bash
./deploy-to-production.sh
```

**What it does:**
- Stops production OpenClaw
- Creates backup (`~/.openclaw-backup-YYYYMMDD-HHMMSS/`)
- Copies new build to production
- Ready to start

**Safety features:**
- Requires explicit "yes" confirmation
- Creates timestamped backup
- Preserves original files

### 5. Rollback (if needed)

```bash
# List available backups
ls -lt ~/.openclaw-backup-*

# Rollback to specific backup
./scripts/rollback-production.sh ~/.openclaw-backup-20260203-143000
```

**What it does:**
- Stops production OpenClaw
- Creates emergency save of current state
- Restores from backup
- Ready to restart

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TEST_PORT` | 3457 | Port for test instance |
| `TEST_BOT_TOKEN` | - | Optional: different Telegram bot for testing |
| `OPENCLAW_CONFIG_DIR` | ~/.openclaw | Production config directory |

## File Locations

### Production
- **Install**: `~/.openclaw/`
- **Config**: `~/.openclaw/config/`
- **Data**: `~/.openclaw/data/`
- **Port**: 3000

### Test
- **Build**: `/tmp/openclaw-test-build-XXXXX/`
- **Config**: `~/.openclaw-test/config/`
- **Data**: `~/.openclaw-test/data/`
- **Port**: 3457

### Backups
- **Location**: `~/.openclaw-backup-YYYYMMDD-HHMMSS/`
- **Contents**: `dist/` and `node_modules/`

## Troubleshooting

### Build Fails

```bash
# Check Node.js version
node --version  # Should be 18+

# Clear npm cache
npm cache clean --force

# Try again
./scripts/safe-test-build.sh
```

### Test Instance Won't Start

```bash
# Check if port is in use
lsof -Pi :3457

# Kill existing process
kill $(lsof -t -i:3457)

# Try again
```

### Validation Fails

```bash
# Check test logs
tail -100 /tmp/test-openclaw.log

# Check if process is running
ps aux | grep openclaw
```

### Deployment Issues

```bash
# Check backup was created
ls -lt ~/.openclaw-backup-*

# Rollback immediately
./scripts/rollback-production.sh ~/.openclaw-backup-XXXXX
```

## Safety Features

1. **Process Isolation**: Test runs on different port
2. **Config Isolation**: Test uses separate config directory
3. **Build Isolation**: Test builds in `/tmp/`, not production
4. **Automatic Backups**: Every deployment creates backup
5. **Confirmation Prompts**: No accidental deployments
6. **One-Command Rollback**: Instant recovery if issues
7. **Emergency Saves**: Rollback creates its own backup

## CI/CD Integration

You can integrate this into GitHub Actions:

```yaml
- name: Test Build
  run: ./scripts/safe-test-build.sh

- name: Start Test Instance
  run: |
    cd /tmp/openclaw-test-build-*
    ./test-launch.sh &
    sleep 10

- name: Validate
  run: |
    cd /tmp/openclaw-test-build-*
    ./validate.sh
```

## Best Practices

1. **Always test before deploying** - Even for small changes
2. **Keep backups** - Don't delete backup directories
3. **Test custom features** - Verify your modifications work
4. **Monitor logs** - Check for errors after deployment
5. **Have rollback ready** - Know the backup location
6. **Use separate bot for testing** (optional) - Avoid spamming your main bot

## Commands Reference

| Command | Purpose |
|---------|---------|
| `./scripts/safe-test-build.sh` | Build test version |
| `./test-launch.sh` | Start test instance |
| `./validate.sh` | Validate test instance |
| `./deploy-to-production.sh` | Deploy to production |
| `./scripts/rollback-production.sh` | Rollback to backup |
| `./scripts/full-test-and-deploy.sh` | Complete workflow |
