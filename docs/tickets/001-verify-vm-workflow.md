# Ticket 001: Verify VM Workflow

**Status**: PLANNING
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Verify that the VM testing workflow works end-to-end on macOS Apple Silicon:
- linux-builder setup and configuration
- Building the server-vm NixOS configuration
- Booting the VM with QEMU
- Accessing services (Homepage on port 3000, SSH on port 2222)

This is a prerequisite for all other development work - we need a working feedback loop.

## Implementation Plan

[To be discussed]

## Open Questions

- Is linux-builder already configured on this machine?
- Are there any issues with the current nix.custom.conf setup?
- Does the VM boot successfully and are services accessible?

## Work Log

### 2026-01-29

- Ticket created
- Awaiting planning discussion with user
