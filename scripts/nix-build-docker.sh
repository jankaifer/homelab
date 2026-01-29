#!/bin/bash
# Build NixOS configurations using Docker
# This avoids the complexity of linux-builder SSH setup
#
# Note: The result symlink points to a nix store path inside Docker.
# Use run-vm-docker.sh to build AND run the VM inside Docker with port forwarding.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default to building server-vm if no argument provided
TARGET="${1:-.#nixosConfigurations.server-vm.config.system.build.vm}"

echo "Building $TARGET using Docker..."
echo "Project: $PROJECT_DIR"
echo ""
echo "Note: Result will be in Docker's nix store. Use run-vm-docker.sh to run the VM."
echo ""

# Use named volume to persist nix store between builds
docker run --rm \
    -v "$PROJECT_DIR:/workspace" \
    -v homelab-nix-store:/nix \
    -w /workspace \
    nixos/nix:latest \
    sh -c "
        mkdir -p /etc/nix
        echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
        nix build '$TARGET' -o /workspace/result
    "

echo ""
echo "Build complete!"
echo ""
echo "To run the VM, use:"
echo "  ./scripts/run-vm-docker.sh"
