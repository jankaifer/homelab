# Ticket 039: OpenClaw Always-On Personal Assistant

**Status**: IN_PROGRESS
**Created**: 2026-05-01
**Updated**: 2026-05-02

## Task

Deploy OpenClaw as an always-on personal assistant service in the homelab. The initial goal is a secure, reachable assistant that can help with coding and personal workflows, then later draft email replies without sending them automatically.

OpenClaw must be deployed behind the SSO foundation from Ticket 025 before it is exposed through the public reverse proxy.

## Implementation Plan

1. Research the current OpenClaw deployment model and choose the least-stateful packaging approach compatible with NixOS:
   - prefer a NixOS module if OpenClaw can run from a pinned package or built derivation
   - otherwise use an OCI container pinned to an immutable image digest
   - avoid mutable global `npm install -g` style deployment for production
2. Create `modules/services/openclaw.nix` with the usual `homelab.services.openclaw.enable` option.
3. Run OpenClaw as a dedicated unprivileged service user.
4. Put all external access behind Caddy and Authelia forward-auth from Ticket 025.
5. Keep service secrets in agenix:
   - OpenClaw application/session secrets
   - model provider API keys
   - LiteLLM key or internal token if LiteLLM is introduced
   - messaging channel credentials
   - Gmail OAuth/client credentials when email drafting is added
6. Start with minimal capabilities:
   - one private management UI or gateway endpoint
   - one private chat channel if needed
   - no broad filesystem access
   - no Docker socket access unless explicitly justified
   - no ability to send email
7. Add model routing through a local LiteLLM proxy or equivalent OpenAI-compatible endpoint:
   - cheap default model for routine assistant work
   - stronger model alias for difficult coding or drafting tasks
   - monthly budget/rate-limit controls before unattended use
8. Add Gmail integration only after the base service is stable:
   - read/search only for selected labels or inbox scope where possible
   - create drafts only
   - never send email without an explicit manual action
   - document the exact scopes granted
9. Add observability:
   - service health checks
   - logs in Loki/Alloy if practical
   - basic dashboard or alerts for crashes/auth failures
   - token/cost tracking if LiteLLM is deployed

## Security Model

- OpenClaw is considered high-risk because it is an always-on agent with access to personal data and tools.
- Public internet exposure must go through Caddy plus Authelia. Direct upstream ports should bind to localhost or an internal interface only.
- Chat/messaging channels must use their own allowlists or pairing controls; SSO at the HTTP edge does not protect a DM-based channel.
- Email automation starts as "draft only". Automatic sending is out of scope for the first implementation.
- The assistant should not receive repository-wide or home-directory-wide mounts by default.
- Production secrets must use agenix, not plaintext environment files committed to the repo.

## Open Questions

- Which OpenClaw upstream repository and release channel should be trusted and pinned?
- Does OpenClaw provide a stable container image, or should it be packaged from source?
- Which communication channel should be enabled first: web UI only, Telegram, Signal, Slack, or another private channel?
- Should LiteLLM be implemented as part of this ticket or split into a separate model-routing ticket?
- Which Gmail account and scopes are acceptable for draft creation?

## Dependencies

- Ticket 025: Authelia SSO Foundation
- Existing Caddy module
- agenix secret management
- Optional future LiteLLM/model-routing module

## Acceptance Criteria

- `homelab.services.openclaw.enable` exists and can run OpenClaw as an unprivileged service.
- OpenClaw is reachable only through a Caddy virtual host protected by Authelia.
- Direct service ports are not exposed publicly.
- Required secrets are declared in `secrets/secrets.nix` and loaded from agenix paths.
- Initial model provider configuration works with API keys and has a cheap default model.
- Logs are available through systemd journal and documented for troubleshooting.
- Email integration, if enabled in the first implementation, can create Gmail drafts but cannot send mail automatically.
- Documentation describes access URL, secrets, model configuration, enabled channels, and safety boundaries.
- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'` succeeds.
- VM build succeeds with `./scripts/run-vm-docker.sh --build`.

## Work Log

### 2026-05-01

- Ticket created after deciding to pursue the "real deal" always-on assistant path.
- Captured hard dependency on Authelia/Caddy protection before exposing OpenClaw.
- Set the initial email policy to draft-only so Gmail integration can be useful without granting autonomous send authority.

### 2026-05-02

- Researched current upstream deployment docs. OpenClaw now publishes Docker images and documents Signal through `signal-cli` over HTTP JSON-RPC/SSE.
- Added `modules/services/openclaw.nix` as a first-pass OCI deployment instead of a mutable `npm install -g` host install.
- Pinned the OpenClaw `2026.4.29` image by per-architecture manifest digest for `x86_64-linux` and `aarch64-linux`.
- Enabled the gateway on `frame1` loopback only with no public UI, no Docker socket, and no host filesystem mounts beyond OpenClaw-owned state directories.
- Restricted initial tools to web search/fetch, messaging, and session status. Runtime execution, filesystem access, gateway automation, node/device tools, media tools, and full browser automation are denied.
- Added optional agenix secret declarations for `openclaw.env.age` and `openclaw-signal-account.age`.
- Made Signal activation conditional on `openclaw-signal-account.age` existing so the base gateway can evaluate and boot before the bot number is provisioned.
- Exposed `https://openclaw.frame1.hobitin.eu` through the existing Caddy protected virtual-host path, so requests are authorized by Authelia before reaching the loopback-only OpenClaw gateway.
- Clarified that Signal "bot" setup means a normal dedicated Signal account controlled by `signal-cli`, not a bot-token flow.
- Added `gateway.controlUi.allowedOrigins` for `https://openclaw.frame1.hobitin.eu` so OpenClaw's own Control UI WebSocket origin check accepts the Authelia-protected reverse-proxy origin.
- Switched the exposed OpenClaw UI from browser-supplied gateway token auth to OpenClaw `trusted-proxy` auth. Caddy remains the Authelia boundary, forwards the Authelia identity headers, and injects `X-OpenClaw-Scopes: operator.admin,operator.write,operator.read` for the OpenClaw virtual host.
- Kept the local generated `/var/lib/openclaw/gateway-token` file as fallback state, but stopped passing `OPENCLAW_GATEWAY_TOKEN` into the container while trusted-proxy auth is active.
