#!/bin/bash
# Build and run NixOS VM using Docker
#
# Why Docker?
# - Building NixOS requires Linux (nix derivations are for aarch64-linux)
# - The VM uses virtfs to mount /nix/store at runtime, which only exists in Docker
# - Building standalone disk images requires KVM (not available in Docker on macOS)
#
# Performance note:
# QEMU runs with TCG (software emulation) inside Docker, which is slower than
# native HVF acceleration. This is a tradeoff for development convenience.
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
    # Mount ~/.ssh as read-only for agenix secret decryption in VM
    docker run --rm \
        --network host \
        -v "$PROJECT_DIR:/workspace" \
        -v homelab-nix-store:/nix \
        -v "$HOME/.ssh:/host-ssh:ro" \
        -w /workspace \
        nixos/nix:latest \
        sh -c '
            set -e
            echo "Enabling flakes..."
            mkdir -p /etc/nix
            echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

            echo ""
            echo "Building VM (this may take a while on first run)..."
            nix build .#nixosConfigurations.frame1-vm.config.system.build.vm

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
    echo "  - Caddy HTTP:  http://localhost:8080 -> :80"
    echo "  - Caddy HTTPS: https://localhost:8443 -> :443 (self-signed cert)"
    echo "  - SSH:         localhost:2222 -> :22"
    echo ""

    # Run Docker with:
    # - Named volume for nix store (persists between runs for faster rebuilds)
    # - Host SSH keys mounted for agenix secret decryption
    # - Port forwarding for Caddy (80/443) and SSH (2222)
    # - Interactive mode for QEMU console
    # Note: Using 8080/8443 on host since 80/443 may require root
    docker run -it --rm \
        -v "$PROJECT_DIR:/workspace" \
        -v homelab-nix-store:/nix \
        -v "$HOME/.ssh:/host-ssh:ro" \
        -w /workspace \
        -p 8080:80 \
        -p 8443:443 \
        -p 2222:22 \
        nixos/nix:latest \
        sh -c '
            set -e
            echo "Enabling flakes..."
            mkdir -p /etc/nix
            echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

            echo ""
            echo "Building VM (this may take a while on first run)..."
            nix build .#nixosConfigurations.frame1-vm.config.system.build.vm

            echo ""
            echo "Starting VM..."
            echo "Press Ctrl+A, X to exit QEMU"
            echo ""

            # Run VM with network forwarding to container ports
            # -nographic: No GUI, use serial console (required in Docker)
            QEMU_OPTS="-nographic" \
            QEMU_NET_OPTS="hostfwd=tcp::80-:80,hostfwd=tcp::443-:443,hostfwd=tcp::22-:22" \
            ./result/bin/run-frame1-vm
        '
fi
