# OpenClaw

OpenClaw personal assistant gateway running as a Podman-managed OCI container.

**Status:** enabled on `frame1` with an Authelia-protected UI
**Pattern:** `homelab.services.openclaw.enable`

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `homelab.services.openclaw.enable` | `false` | Enable the OpenClaw gateway container |
| `homelab.services.openclaw.image` | OpenClaw `2026.4.29` pinned per architecture | OCI image to run |
| `homelab.services.openclaw.port` | `18789` | Host-loopback gateway port |
| `homelab.services.openclaw.environmentFile` | `null` | Optional agenix env file for model/search provider keys |
| `homelab.services.openclaw.model` | `null` | Optional explicit default model; overrides the OpenRouter default when set |
| `homelab.services.openclaw.openRouter.enable` | `false` | Configure OpenRouter as the default model provider |
| `homelab.services.openclaw.openRouter.model` | `openrouter/moonshotai/kimi-k2.6` | Cost-efficient Kimi K2.6 default model through OpenRouter |
| `homelab.services.openclaw.allowBrowserTool` | `false` | Allow full browser automation; disabled for the initial deployment |
| `homelab.services.openclaw.exposeUi.enable` | `false` | Expose the control UI through Caddy plus Authelia |
| `homelab.services.openclaw.exposeUi.domain` | `openclaw.frame1.hobitin.eu` | Protected control UI domain |
| `homelab.services.openclaw.signal.enable` | `false` | Enable Signal through a host-side `signal-cli` daemon |
| `homelab.services.openclaw.signal.accountFile` | `null` | File containing the Signal bot account in E.164 format |

## Access

- Gateway: `127.0.0.1:18789` on the host only
- UI: `https://openclaw.frame1.hobitin.eu`, protected by Caddy forward-auth through Authelia
- Signal channel: enabled automatically after `secrets/openclaw-signal-account.age` exists

The container uses host networking so its loopback-bound gateway can be reached by host services and so it can talk to the host-side `signal-cli` daemon. The OpenClaw HTTP surface still binds to loopback, is not opened in the firewall, and is only proxied by Caddy after Authelia authorizes the request.

When the UI is exposed, the module configures OpenClaw gateway auth in `trusted-proxy` mode. Caddy performs Authelia forward-auth, copies the Authelia identity headers, and injects `X-OpenClaw-Scopes: operator.admin,operator.write,operator.read` for the protected OpenClaw host. OpenClaw accepts only the configured Authelia user `jan@kaifer.cz` through loopback trusted proxies.

The module also sets `gateway.controlUi.allowedOrigins` to include `https://openclaw.frame1.hobitin.eu`. This is required by OpenClaw's own browser-origin check; the error screen may display `controlUI`, but the valid config key is `controlUi`.

## Safety Boundary

The first deployment intentionally allows only:

- `group:web` for web search/fetch
- `message` for replying through configured channels
- `session_status` for lightweight status checks

It denies runtime execution, filesystem tools, automation/gateway tools, node/device tools, media generation, and the full browser UI tool. No Docker socket is mounted. No host home directory, repository directory, NAS path, or credential directory is mounted into the container.

Full browser automation is not enabled yet. Upstream documents that the standard container image does not include Chromium unless built with browser support, so enabling `allowBrowserTool` should be paired with a reviewed browser-capable image and another security pass.

## Secrets

Optional secrets declared in `secrets/secrets.nix`:

- `openclaw.env.age`: env file for provider keys. For the default OpenRouter setup, it must contain `OPENROUTER_API_KEY=sk-or-...`. It may also contain search/provider keys such as `BRAVE_API_KEY=...`.
- `openclaw-signal-account.age`: one-line Signal bot account, for example `+15551234567`

The module keeps a generated local gateway token at `/var/lib/openclaw/gateway-token` as fallback state, but trusted-proxy mode does not pass `OPENCLAW_GATEWAY_TOKEN` into the OpenClaw container. If `openclaw.env.age` exists, any `OPENCLAW_GATEWAY_TOKEN=` line in it is filtered out before the container env file is generated.

On `frame1`, `homelab.services.openclaw.openRouter.enable` is turned on only when `secrets/openclaw.env.age` exists. When enabled and no explicit `homelab.services.openclaw.model` override is set, OpenClaw writes `agents.defaults.model.primary = "openrouter/moonshotai/kimi-k2.6"` into its generated config. The bootstrap service preserves OpenClaw's `meta.lastTouchedVersion` field when rewriting `/var/lib/openclaw/openclaw.json`; OpenClaw 2026.4.29 treats a generated config without that metadata as stale and may restore the previous backup, which can drop the default model.

## Signal Setup

Use a dedicated Signal bot number if possible. Signal does not have a Telegram-style bot token. In this setup, the "bot" is just a normal Signal account controlled by `signal-cli`.

Using the same Signal account you already use personally is possible only as a linked device, but it is awkward for "I text the bot and it replies" because the assistant is effectively logged in as you. A separate account is cleaner: you message that account from your normal Signal app, and OpenClaw replies as that account.

After deploying the secret and service, link or register the account as `openclaw-signal`:

```bash
sudo -u openclaw-signal signal-cli --config /var/lib/openclaw-signal link -n "OpenClaw"
```

Then restart and approve the first DM pairing:

```bash
sudo systemctl restart openclaw-signal podman-openclaw
sudo podman exec openclaw node openclaw.mjs pairing list signal
sudo podman exec openclaw node openclaw.mjs pairing approve signal <CODE>
```

## Operations

Check status:

```bash
systemctl status podman-openclaw
systemctl status openclaw-signal
```

Logs:

```bash
journalctl -u podman-openclaw -n 200 --no-pager
journalctl -u openclaw-signal -n 200 --no-pager
```

Health:

```bash
curl -fsS http://127.0.0.1:18789/healthz
curl -fsS http://127.0.0.1:18789/readyz
```

## Upstream References

- [OpenClaw Docker install](https://docs.openclaw.ai/install/docker)
- [OpenClaw Signal channel](https://docs.openclaw.ai/channels/signal)
- [OpenClaw tools configuration](https://docs.openclaw.ai/tools/index)
- [OpenClaw security guidance](https://docs.openclaw.ai/gateway/security)
