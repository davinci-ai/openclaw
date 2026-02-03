# Docker Testing & Deployment Guide

This guide explains how to use Docker for completely isolated testing and safe deployment of your custom OpenClaw fork.

## Why Docker?

- **True isolation**: Containers don't share anything with host
- **Consistent environment**: Same Node.js version, same dependencies
- **Easy cleanup**: Remove containers/images without affecting system
- **Health checks**: Built-in monitoring
- **Port mapping**: Easy to run multiple instances

## Quick Start

### Option 1: Full Automated Workflow

```bash
./scripts/docker-full-workflow.sh
```

Builds → Tests → Validates → Deploys (with confirmation)

### Option 2: Step by Step

```bash
# Build and test
./scripts/docker-test-deploy.sh test

# Test manually at http://localhost:3457

# Deploy when ready
./scripts/docker-test-deploy.sh deploy
```

## Architecture

```
┌─────────────────────────────────────────┐
│           Docker Host                   │
│  ┌─────────────────────────────────┐   │
│  │   openclaw-production           │   │
│  │   Port: 3000 (production)       │   │
│  │   Volumes: prod-config, prod-data│  │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │   openclaw-test                 │   │
│  │   Port: 3457 (test)             │   │
│  │   Volumes: test-config, test-data│  │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## Commands

### Test (Isolated)

```bash
./scripts/docker-test-deploy.sh test
```

**What happens:**
1. Builds Docker image (`openclaw:test`)
2. Starts test container on port 3457
3. Runs health checks
4. Shows logs

**Access:** http://localhost:3457

### Deploy to Production

```bash
./scripts/docker-test-deploy.sh deploy
```

**What happens:**
1. Tags test image as production
2. Creates versioned backup image
3. Stops old production container
4. Starts new production container
5. Runs health checks

**Access:** http://localhost:3000

### Rollback

```bash
# List available versions
./scripts/docker-test-deploy.sh rollback

# Or specify directly
./scripts/docker-test-deploy.sh rollback
# Then enter tag like: prod-20260203-143000
```

### Cleanup

```bash
./scripts/docker-test-deploy.sh cleanup
```

Removes test containers and images (production stays running).

## Docker Compose Services

### Production Service (`openclaw-prod`)

```yaml
container_name: openclaw-production
ports:
  - "3000:3000"        # Production port
volumes:
  - openclaw-prod-config:/app/config
  - openclaw-prod-data:/app/data
restart: unless-stopped
```

### Test Service (`openclaw-test`)

```yaml
container_name: openclaw-test
ports:
  - "3457:3000"        # Test port (mapped to container's 3000)
volumes:
  - openclaw-test-config:/app/config
  - openclaw-test-data:/app/data
profiles:
  - test               # Only started with --profile test
```

## Manual Docker Commands

### Build

```bash
docker build -t openclaw:test -f Dockerfile .
```

### Run Test Container

```bash
docker run -d \
  --name openclaw-test \
  -p 3457:3000 \
  -v openclaw-test-config:/app/config \
  -v openclaw-test-data:/app/data \
  openclaw:test
```

### View Logs

```bash
# Test container
docker logs -f openclaw-test

# Production container
docker logs -f openclaw-production
```

### Execute Commands

```bash
# Shell into container
docker exec -it openclaw-test sh

# Check processes
docker exec openclaw-test ps aux
```

### Stop and Remove

```bash
# Stop test
docker stop openclaw-test
docker rm openclaw-test

# Stop production
docker-compose stop openclaw-prod
```

## Data Persistence

Docker volumes persist data between container restarts:

| Volume | Purpose | Container Path |
|--------|---------|----------------|
| `openclaw-prod-config` | Production config | `/app/config` |
| `openclaw-prod-data` | Production data | `/app/data` |
| `openclaw-test-config` | Test config | `/app/config` |
| `openclaw-test-data` | Test data | `/app/data` |

### Backup Volumes

```bash
# Backup production config
docker run --rm -v openclaw-prod-config:/source -v $(pwd):/backup alpine tar czf /backup/prod-config-backup.tar.gz -C /source .

# Restore
docker run --rm -v openclaw-prod-config:/target -v $(pwd):/backup alpine tar xzf /backup/prod-config-backup.tar.gz -C /target
```

## Health Checks

The Dockerfile includes a health check:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', ...)"
```

Check container health:

```bash
docker ps
# Look for (healthy) or (unhealthy) in STATUS

# Detailed health
docker inspect --format='{{.State.Health.Status}}' openclaw-production
```

## Troubleshooting

### Build Fails

```bash
# Clear build cache
docker build --no-cache -t openclaw:test .

# Check Docker daemon
docker info
```

### Container Won't Start

```bash
# Check logs
docker logs openclaw-test

# Check port conflicts
lsof -Pi :3457

# Check disk space
docker system df
```

### Can't Connect to Container

```bash
# Verify port mapping
docker port openclaw-test

# Test from inside container
docker exec openclaw-test wget -qO- http://localhost:3000/health

# Test from host
curl http://localhost:3457/health
```

### Cleanup Everything

```bash
# Stop all containers
docker-compose down

# Remove test containers
docker rm -f openclaw-test

# Remove images
docker rmi openclaw:test openclaw:prod-latest

# Remove volumes (WARNING: deletes data!)
docker volume rm openclaw-test-config openclaw-test-data
```

## Comparison: Docker vs Non-Docker

| Feature | Non-Docker | Docker |
|---------|-----------|--------|
| Isolation | Process-level | OS-level (complete) |
| Cleanup | Manual file removal | `docker rm` |
| Port conflicts | Possible | Mapped ports |
| Dependencies | Host Node.js | Container Node.js |
| Rollback | File backup | Image tags |
| Health checks | External script | Built-in |

## Production Deployment Checklist

Before deploying to production:

- [ ] Test container builds successfully
- [ ] Test container starts without errors
- [ ] Health check passes
- [ ] Custom features tested (Kimi thinking, plugins)
- [ ] Logs show no critical errors
- [ ] Production backup available (previous image)
- [ ] Rollback procedure understood

## Advanced Usage

### Multi-Stage Build

The Dockerfile uses multi-stage builds:

1. **Builder stage**: Compiles TypeScript, installs all dependencies
2. **Production stage**: Only runtime files, smaller image

### Custom Environment Variables

Create `.env` file:

```bash
TELEGRAM_BOT_TOKEN=your_token
OPENROUTER_API_KEY=your_key
LOG_LEVEL=info
```

Load in docker-compose:

```yaml
env_file:
  - .env
```

### Resource Limits

Add to docker-compose.yml:

```yaml
services:
  openclaw-prod:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 512M
```

## Migration from Non-Docker

If you're currently running OpenClaw without Docker:

1. **Backup your data:**
   ```bash
   cp -r ~/.openclaw ~/openclaw-backup-$(date +%Y%m%d)
   ```

2. **Copy config to Docker volume:**
   ```bash
   # Create volume
   docker volume create openclaw-prod-config
   
   # Copy existing config
   docker run --rm \
     -v openclaw-prod-config:/target \
     -v ~/.openclaw/config:/source:ro \
     alpine cp -r /source/* /target/
   ```

3. **Start with Docker:**
   ```bash
   ./scripts/docker-full-workflow.sh
   ```

## Security Notes

- Containers run as non-root user (`openclaw`)
- Only necessary ports exposed
- No sensitive data in images
- Volumes for persistent data
- Health checks prevent routing to unhealthy containers
