#!/usr/bin/env bash
# Install NixOS on a new server using nixos-anywhere
#
# Prerequisites:
# 1. Boot target machine from NixOS minimal ISO
# 2. Ensure SSH is accessible (default on installer)
# 3. Run this script from your local machine
#
# Usage:
#   ./scripts/install-server.sh <target-ip>
#   ./scripts/install-server.sh 192.168.1.100
#
# The script will:
# 1. Generate a new SSH host key for the server
# 2. Update secrets.nix with the public key
# 3. Re-encrypt all secrets so the server can decrypt them
# 4. Run nixos-anywhere to partition disk and install NixOS
# 5. Copy the SSH host key to the server
# 6. Reboot into the configured system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$REPO_DIR/secrets"
SECRETS_NIX="$SECRETS_DIR/secrets.nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <target-ip> [options]"
    echo ""
    echo "Options:"
    echo "  --disk DEVICE    Override disk device (default: /dev/nvme0n1)"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100"
    echo "  $0 192.168.1.100 --disk /dev/sda"
    exit 1
}

log() {
    echo -e "${GREEN}==>${NC} $1"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1"
    exit 1
}

# Parse arguments
TARGET_IP=""
DISK_DEVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --disk)
            DISK_DEVICE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [[ -z "$TARGET_IP" ]]; then
                TARGET_IP="$1"
            else
                error "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET_IP" ]]; then
    error "Target IP address required"
fi

# Check that agenix is available
if ! command -v agenix &> /dev/null; then
    # Try running via nix
    if ! nix run github:ryantm/agenix -- --help &> /dev/null; then
        error "agenix not found. Install it or ensure 'nix run github:ryantm/agenix' works"
    fi
    AGENIX_CMD="nix run github:ryantm/agenix --"
else
    AGENIX_CMD="agenix"
fi

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════╗"
echo "║       NixOS Server Installation           ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo "Target:     root@$TARGET_IP"
echo "Flake:      $REPO_DIR#server"
if [[ -n "$DISK_DEVICE" ]]; then
    echo "Disk:       $DISK_DEVICE (override)"
else
    echo "Disk:       /dev/nvme0n1 (default from disko.nix)"
fi
echo ""

# Confirm before proceeding
echo -e "${YELLOW}WARNING: This will ERASE ALL DATA on the target disk!${NC}"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Create temporary directory for SSH key and extra files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

SSH_KEY="$TEMP_DIR/ssh_host_ed25519_key"
SSH_KEY_PUB="$TEMP_DIR/ssh_host_ed25519_key.pub"

# Step 1: Generate SSH host key
log "Generating SSH host key for server..."
ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "server-host-key" -q
SERVER_PUBKEY=$(cat "$SSH_KEY_PUB" | awk '{print $1 " " $2}')
echo "  Public key: ${SERVER_PUBKEY:0:50}..."

# Step 2: Update secrets.nix with the new public key
log "Updating secrets.nix with server public key..."

# Check if placeholder exists
if ! grep -q "INSTALL_SERVER_KEY_PLACEHOLDER" "$SECRETS_NIX"; then
    error "Could not find INSTALL_SERVER_KEY_PLACEHOLDER in secrets.nix"
fi

# Replace the server key line (the line after the placeholder comment)
# We look for the pattern: server = "ssh-ed25519 ...";
sed -i.bak -E "s|server = \"ssh-ed25519 [^\"]+\";|server = \"$SERVER_PUBKEY\";|" "$SECRETS_NIX"
rm -f "$SECRETS_NIX.bak"

echo "  Updated: $SECRETS_NIX"

# Step 3: Re-encrypt secrets
log "Re-encrypting secrets with new server key..."
cd "$SECRETS_DIR"
$AGENIX_CMD -r
cd "$REPO_DIR"
echo "  Secrets re-encrypted"

# Step 4: Prepare extra files (SSH host key)
log "Preparing installation files..."
EXTRA_FILES_DIR="$TEMP_DIR/extra-files"
mkdir -p "$EXTRA_FILES_DIR/etc/ssh"
cp "$SSH_KEY" "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key"
cp "$SSH_KEY_PUB" "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key.pub"
chmod 600 "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key"
chmod 644 "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key.pub"

# Step 5: Build nixos-anywhere command
NIXOS_ANYWHERE_ARGS=(
    "--flake" "$REPO_DIR#server"
    "--target-host" "root@$TARGET_IP"
    "--extra-files" "$EXTRA_FILES_DIR"
)

# Note about disk override
if [[ -n "$DISK_DEVICE" ]]; then
    warn "Disk override requires modifying machines/server/disko.nix"
    echo "  Set: disko.devices.disk.main.device = \"$DISK_DEVICE\";"
    echo ""
    read -p "Have you updated disko.nix? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please update disko.nix first, then re-run this script."
        exit 1
    fi
fi

# Step 6: Run nixos-anywhere
log "Running nixos-anywhere (this will take a while)..."
echo ""
nix run github:nix-community/nixos-anywhere -- "${NIXOS_ANYWHERE_ARGS[@]}"

echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════╗"
echo "║       Installation Complete!              ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "The server is rebooting into NixOS."
echo ""
echo "Once it's up, connect with:"
echo "  ssh root@$TARGET_IP"
echo ""
echo "Default credentials (change these!):"
echo "  root password: nixos"
echo "  admin password: nixos"
echo ""
echo -e "${YELLOW}Don't forget to commit the updated secrets.nix!${NC}"
echo "  git add secrets/"
echo "  git commit -m 'Update server SSH key after installation'"
