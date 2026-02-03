#!/bin/bash
# setup-podman-macos.sh - Install and configure Podman on macOS
# Usage: ./scripts/setup-podman-macos.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "========================================"
echo "  Podman Setup for macOS"
echo "========================================"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is for macOS only"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
log_info "Architecture: $ARCH"

# Step 1: Check if Homebrew is installed
log_step "Step 1: Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    log_warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add to PATH for Apple Silicon Macs
    if [[ "$ARCH" == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    log_info "✓ Homebrew is installed"
fi

# Step 2: Install Podman
log_step "Step 2: Installing Podman..."
if command -v podman &> /dev/null; then
    log_info "✓ Podman already installed: $(podman --version)"
    read -p "Reinstall/Update Podman? (y/N): " update
    if [[ "$update" =~ ^[Yy]$ ]]; then
        brew reinstall podman
    fi
else
    log_info "Installing Podman..."
    brew install podman
    log_info "✓ Podman installed"
fi

# Step 3: Install podman-compose
log_step "Step 3: Installing podman-compose..."
if command -v podman-compose &> /dev/null; then
    log_info "✓ podman-compose already installed"
else
    log_info "Installing podman-compose..."
    brew install podman-compose
    log_info "✓ podman-compose installed"
fi

# Step 4: Initialize Podman machine
log_step "Step 4: Setting up Podman machine..."

# Check if machine exists
if podman machine list | grep -q "podman-machine-default"; then
    log_info "✓ Podman machine already exists"
    
    # Check if running
    if podman machine list | grep "podman-machine-default" | grep -q "Running"; then
        log_info "✓ Podman machine is running"
    else
        log_info "Starting Podman machine..."
        podman machine start
        log_info "✓ Podman machine started"
    fi
else
    log_info "Creating Podman machine..."
    
    # Detect total memory and allocate reasonably
    TOTAL_MEM_GB=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    log_info "Total system memory: ${TOTAL_MEM_GB}GB"
    
    # Allocate 1/4 of memory, min 2GB, max 8GB
    VM_MEM=$((TOTAL_MEM_GB / 4))
    if [ $VM_MEM -lt 2 ]; then VM_MEM=2; fi
    if [ $VM_MEM -gt 8 ]; then VM_MEM=8; fi
    
    log_info "Allocating ${VM_MEM}GB to Podman VM"
    
    # Create machine with appropriate resources
    podman machine init \
        --cpus 4 \
        --memory $((VM_MEM * 1024)) \
        --disk-size 50 \
        --now
    
    log_info "✓ Podman machine created and started"
fi

# Step 5: Verify installation
log_step "Step 5: Verifying installation..."

podman --version
podman info --format "{{.Host.Architecture}}" > /dev/null 2>&1 && log_info "✓ Podman is working"

# Test run a container
if podman run --rm hello-world 2>/dev/null | grep -q "Hello from Docker"; then
    log_info "✓ Container test passed"
else
    log_warn "Container test had issues, but Podman should still work"
fi

# Step 6: Setup shell integration
log_step "Step 6: Setting up shell integration..."

SHELL_RC=""
if [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_RC="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
    # Add podman alias if not exists
    if ! grep -q "alias docker=podman" "$SHELL_RC"; then
        echo "" >> "$SHELL_RC"
        echo "# Podman alias for Docker compatibility" >> "$SHELL_RC"
        echo "alias docker=podman" >> "$SHELL_RC"
        log_info "✓ Added podman alias to $SHELL_RC"
    fi
    
    # Add podman-compose alias if not exists
    if ! grep -q "alias docker-compose=podman-compose" "$SHELL_RC"; then
        echo "alias docker-compose='podman-compose'" >> "$SHELL_RC"
        log_info "✓ Added podman-compose alias to $SHELL_RC"
    fi
fi

# Step 7: Create convenient scripts
log_step "Step 7: Creating helper scripts..."

# Create podman-start script
cat > "$HOME/.local/bin/podman-start" << 'EOF'
#!/bin/bash
# Start Podman VM

if podman machine list | grep "podman-machine-default" | grep -q "Running"; then
    echo "Podman machine is already running"
else
    echo "Starting Podman machine..."
    podman machine start
    echo "✓ Podman machine started"
fi
EOF
chmod +x "$HOME/.local/bin/podman-start"

# Create podman-stop script
cat > "$HOME/.local/bin/podman-stop" << 'EOF'
#!/bin/bash
# Stop Podman VM to save resources

echo "Stopping Podman machine..."
podman machine stop
echo "✓ Podman machine stopped"
EOF
chmod +x "$HOME/.local/bin/podman-stop"

log_info "✓ Helper scripts created in ~/.local/bin/"

# Step 8: Final verification
echo ""
log_step "Step 8: Final verification..."
echo ""

echo "Podman version:"
podman --version
echo ""

echo "Podman machine status:"
podman machine list
echo ""

echo "Test container:"
podman run --rm alpine echo "✓ Podman is working!"
echo ""

# Summary
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Podman is ready to use!"
echo ""
echo "Quick commands:"
echo "  podman ps              - List running containers"
echo "  podman images          - List images"
echo "  podman-start           - Start Podman VM"
echo "  podman-stop            - Stop Podman VM (save battery)"
echo ""
echo "Test OpenClaw:"
echo "  ./scripts/podman-test-deploy.sh test"
echo ""
echo "Notes:"
echo "  - Podman VM uses ~${VM_MEM}GB RAM when running"
echo "  - Stop VM when not needed: podman-stop"
echo "  - Aliases added: docker=podman, docker-compose=podman-compose"
echo ""
echo "To use in current shell:"
echo "  source $SHELL_RC"
echo ""
