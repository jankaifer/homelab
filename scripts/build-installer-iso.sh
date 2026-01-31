#!/bin/bash
# Build installer ISO using Docker
#
# Decrypts WiFi password from agenix and builds x86_64-linux ISO.
# Output: result/iso/nixos-*.iso
#
# Usage:
#   ./scripts/build-installer-iso.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building installer ISO..."
echo ""

# Decrypt WiFi password from agenix (requires your SSH key)
echo "Decrypting WiFi password..."
WIFI_PASSWORD=$(cd "$PROJECT_DIR/secrets" && age -d -i ~/.ssh/id_ed25519 wifi-password.age 2>/dev/null) || {
    echo "Failed to decrypt wifi-password.age"
    echo "Make sure ~/.ssh/id_ed25519 matches one of the keys in lib/ssh-keys.nix"
    exit 1
}
export WIFI_PASSWORD

echo "Building ISO in Docker (x86_64-linux)..."
echo ""

docker run --rm \
    --network host \
    -v "$PROJECT_DIR:/workspace" \
    -v homelab-nix-store:/nix \
    -w /workspace \
    -e WIFI_PASSWORD="$WIFI_PASSWORD" \
    nixos/nix:latest \
    sh -c '
        set -e
        echo "Enabling flakes..."
        mkdir -p /etc/nix
        echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

        echo ""
        echo "Building installer ISO (this may take a while on first run)..."
        nix build .#nixosConfigurations.installer-iso.config.system.build.isoImage --impure

        echo ""
        echo "Build complete!"
        ls -lh result/iso/
    '

echo ""
echo "ISO built successfully!"
echo "Output: $PROJECT_DIR/result/iso/"
echo ""
echo "Flash to USB with:"
echo "  sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress"
