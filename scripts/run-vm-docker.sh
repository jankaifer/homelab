#!/bin/bash
# Build and run NixOS VM entirely in Docker
# This handles the fact that nix store paths aren't accessible from macOS
#
# Usage:
#   ./run-vm-docker.sh          # Build and run VM interactively
#   ./run-vm-docker.sh --build  # Build only (can run in background)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BUILD_ONLY=false
if [[ "$1" == "--build" ]]; then
    BUILD_ONLY=true
fi

echo "Project: $PROJECT_DIR"
echo ""

if [[ "$BUILD_ONLY" == "true" ]]; then
    echo "Building NixOS VM in Docker (build only mode)..."
    echo ""

    # Use --network host to avoid DNS issues in Docker
    docker run --rm \
        --network host \
        -v "$PROJECT_DIR:/workspace" \
        -v homelab-nix-store:/nix \
        -w /workspace \
        nixos/nix:latest \
        sh -c '
            set -e
            echo "Enabling flakes..."
            mkdir -p /etc/nix
            echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

            echo ""
            echo "Building VM (this may take a while on first run)..."
            nix build .#nixosConfigurations.server-vm.config.system.build.vm

            echo ""
            echo "Build complete!"
        '

    echo ""
    echo "Build finished. To run the VM:"
    echo "  ./scripts/run-vm-docker.sh"
else
    echo "Building and running NixOS VM in Docker..."
    echo ""
    echo "Ports forwarded:"
    echo "  - Homepage: http://localhost:3000"
    echo "  - SSH: localhost:2222"
    echo ""

    # Run Docker with:
    # - Named volume for nix store (persists between runs for faster rebuilds)
    # - Port forwarding for Homepage (3000) and SSH (2222)
    # - Interactive mode for QEMU console
    docker run -it --rm \
        -v "$PROJECT_DIR:/workspace" \
        -v homelab-nix-store:/nix \
        -w /workspace \
        -p 3000:3000 \
        -p 2222:22 \
        nixos/nix:latest \
        sh -c '
            set -e
            echo "Enabling flakes..."
            mkdir -p /etc/nix
            echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

            echo ""
            echo "Building VM (this may take a while on first run)..."
            nix build .#nixosConfigurations.server-vm.config.system.build.vm

            echo ""
            echo "Starting VM..."
            echo "Press Ctrl+A, X to exit QEMU"
            echo ""

            # Run VM with network forwarding to container ports
            QEMU_NET_OPTS="hostfwd=tcp::3000-:3000,hostfwd=tcp::22-:22" ./result/bin/run-server-vm
        '
fi
