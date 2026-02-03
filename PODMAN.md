# Podman Testing & Deployment Guide

Podman is the preferred container runtime for OpenClaw testing and deployment.

## Why Podman?

| Feature | Podman | Docker |
|---------|--------|--------|
| **Rootless** | ✅ Default | ❌ Requires setup |
| **Daemonless** | ✅ No daemon | ❌ Requires daemon |
| **Security** | ✅ Fork/exec model | ❌ Client/server |
| **Compatibility** | ✅ Drop-in replacement | - |
| **Kubernetes** | ✅ Native pods | ❌ Needs compose |

## Installation

### macOS

```bash
brew install podman
podman machine init
podman machine start
```

### Linux

```bash
# Fedora/RHEL
sudo dnf install podman podman-compose

# Ubuntu/Debian
sudo apt-get install podman podman-compose

# Arch
sudo pacman -S podman podman-compose
```

### Verify Installation

```bash
podman --version
podman info
```

## Quick Start

### Option 1: Full Automated Workflow

```bash
./scripts/podman-full-workflow.sh
```

### Option 2: Step by Step

```bash
# Build and test
./scripts/podman-test-deploy.sh test

# Test manually at http://localhost:3457

# Deploy when ready
./scripts/podman-test-deploy.sh deploy
```

## Rootless Containers

Podman runs containers as your user by default - no root needed!

```bash
# Check current user
id

# Run container (no sudo!)
podman run -d --name test nginx

# Check it's running as you
ps aux | grep nginx
```

### User Namespace

Podman automatically maps container root to your user:

```bash
# Inside container: you appear as root
podman exec -it openclaw-test id
# uid=0(root) gid=0(root)

# On host: you're just your user
id
# uid=1000(youruser) gid=1000(youruser)
```

## Commands

### Test (Isolated)

```bash
./scripts/podman-test-deploy.sh test
```

Runs rootless container on port 3457.

### Deploy to Production

```bash
./scripts/podman-test-deploy.sh deploy
```

Deploys to port 3000 with auto-restart.

### Rollback

```bash
./scripts/podman-test-deploy.sh rollback
```

Select from previous image tags.

### Cleanup

```bash
./scripts/podman-test-deploy.sh cleanup
```

## Podman vs Docker Commands

| Task | Podman | Docker |
|------|--------|--------|
| Build | `podman build` | `docker build` |
| Run | `podman run` | `docker run` |
| List | `podman ps` | `docker ps` |
| Logs | `podman logs` | `docker logs` |
| Stop | `podman stop` | `docker stop` |
| Remove | `podman rm` | `docker rm` |
| Images | `podman images` | `docker images` |
| Exec | `podman exec` | `docker exec` |

**They're identical!** The scripts auto-detect and use whichever is available.

## Podman-Specific Features

### Pods (Groups of Containers)

```bash
# Create a pod
podman pod create --name openclaw-pod -p 3000:3000

# Add containers to pod
podman run -d --pod openclaw-pod --name openclaw-app openclaw:prod-latest
podman run -d --pod openclaw-pod --name openclaw-logs fluentd
```

### Generate Kubernetes YAML

```bash
# Export running container to K8s YAML
podman generate kube openclaw-production > openclaw.yaml

# Apply to Kubernetes
kubectl apply -f openclaw.yaml
```

### Systemd Integration

```bash
# Generate systemd service
podman generate systemd --new --name openclaw-production > ~/.config/systemd/user/openclaw.service

# Enable and start
systemctl --user enable --now openclaw

# Check status
systemctl --user status openclaw
```

## Rootful vs Rootless

### Rootless (Default, Recommended)

```bash
# No sudo needed
podman run -d -p 3000:3000 openclaw:prod-latest

# Containers run as your user
ps aux | grep openclaw
# Shows your username, not root
```

**Limitations:**
- Can't bind to ports < 1024 (unless configured)
- Some networking features limited

### Rootful (If Needed)

```bash
sudo podman run -d -p 80:3000 openclaw:prod-latest
```

## Networking

### Port Mapping

```bash
# Rootless: maps to localhost only
podman run -d -p 3000:3000 openclaw:prod-latest
# Accessible at: http://localhost:3000

# To expose to network (rootful only)
sudo podman run -d -p 0.0.0.0:3000:3000 openclaw:prod-latest
```

### Custom Network

```bash
# Create network
podman network create openclaw-net

# Use network
podman run -d --network openclaw-net --name openclaw openclaw:prod-latest
```

## Storage

### Volumes (Rootless)

Stored in: `~/.local/share/containers/storage/volumes/`

```bash
# List volumes
podman volume ls

# Inspect
podman volume inspect openclaw-prod-config
```

### Images (Rootless)

Stored in: `~/.local/share/containers/storage/`

```bash
# List images
podman images

# Remove unused
podman image prune
```

## Troubleshooting

### Port Already in Use

```bash
# Rootless: check if another user has it
ss -tlnp | grep 3000

# Use different port
podman run -d -p 3001:3000 openclaw:prod-latest
```

### Permission Denied

```bash
# Check subuid/subgid
cat /etc/subuid

# Should show: youruser:100000:65536

# If missing, add:
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 youruser
```

### Can't Pull Images

```bash
# Check network
podman run --rm alpine ping -c 3 google.com

# DNS issues?
podman run --rm --dns 8.8.8.8 alpine ping -c 3 google.com
```

### Container Won't Start

```bash
# Check logs
podman logs openclaw-test

# Check SELinux (if enabled)
ls -Z ~/.local/share/containers/

# Try with :Z label
podman run -v openclaw-test-config:/app/config:Z openclaw:test
```

## Migration from Docker

### Automatic Migration

```bash
# Install podman-docker (provides docker compatibility)
sudo dnf install podman-docker  # Fedora

# Or create alias
alias docker=podman
```

### Migrate Volumes

```bash
# Export Docker volume
docker run --rm -v docker-volume:/source -v $(pwd):/backup alpine tar czf /backup/volume.tar.gz -C /source .

# Import to Podman
podman volume create podman-volume
podman run --rm -v podman-volume:/target -v $(pwd):/backup alpine tar xzf /backup/volume.tar.gz -C /target
```

### Migrate Containers

```bash
# Export Docker container
docker export mycontainer > mycontainer.tar

# Import to Podman
podman import mycontainer.tar myimage:latest
```

## Best Practices

1. **Always use rootless** when possible
2. **Regular cleanup**: `podman system prune`
3. **Version your images**: `openclaw:prod-20240203`
4. **Use volumes** for persistent data
5. **Health checks** in containers
6. **Resource limits**: `--memory`, `--cpus`

## Comparison Summary

| Aspect | Podman | Docker |
|--------|--------|--------|
| **Command syntax** | Identical | - |
| **Root required** | No (default) | Yes (default) |
| **Daemon** | No | Yes |
| **Docker Compose** | podman-compose | docker-compose |
| **Kubernetes** | Native support | Needs tools |
| **macOS** | Via machine | Native |
| **Linux** | Native | Native |

## Resources

- [Podman Documentation](https://docs.podman.io/)
- [Podman vs Docker](https://podman.io/whatis.html)
- [Rootless Podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
