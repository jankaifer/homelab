# OpenClaw

OpenClaw personal assistant gateway running as a Podman-managed OCI container.

**Status:** enabled on `frame1` as a first-pass, loopback-only gateway
**Pattern:** `homelab.services.openclaw.enable`

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `homelab.services.openclaw.enable` | `false` | Enable the OpenClaw gateway container |
| `homelab.services.openclaw.image` | OpenClaw `2026.4.29` pinned per architecture | OCI image to run |
| `homelab.services.openclaw.port` | `18789` | Host-loopback gateway port |
| `homelab.services.openclaw.environmentFile` | `null` | Optional agenix env file for model/search provider keys |
| `homelab.services.openclaw.allowBrowserTool` | `false` | Allow full browser automation; disabled for the initial deployment |
| `homelab.services.openclaw.exposeUi.enable` | `false` | Expose the control UI through Caddy plus Authelia |
| `homelab.services.openclaw.signal.enable` | `false` | Enable Signal through a host-side `signal-cli` daemon |
| `homelab.services.openclaw.signal.accountFile` | `null` | File containing the Signal bot account in E.164 format |

## Access

- Gateway: `127.0.0.1:18789` on the host only
- Public UI: disabled for the initial deployment
- Signal channel: enabled automatically after `secrets/openclaw-signal-account.age` exists

The container uses host networking so its loopback-bound gateway can be reached by host services and so it can talk to the host-side `signal-cli` daemon. The OpenClaw HTTP surface still binds to loopback and is not opened in the firewall.

## Safety Boundary

The first deployment intentionally allows only:

- `group:web` for web search/fetch
- `message` for replying through configured channels
- `session_status` for lightweight status checks

It denies runtime execution, filesystem tools, automation/gateway tools, node/device tools, media generation, and the full browser UI tool. No Docker socket is mounted. No host home directory, repository directory, NAS path, or credential directory is mounted into the container.

Full browser automation is not enabled yet. Upstream documents that the standard container image does not include Chromium unless built with browser support, so enabling `allowBrowserTool` should be paired with a reviewed browser-capable image and another security pass.

## Secrets

Optional secrets declared in `secrets/secrets.nix`:

- `openclaw.env.age`: env file for provider keys, for example `OPENAI_API_KEY=...` or `BRAVE_API_KEY=...`
- `openclaw-signal-account.age`: one-line Signal bot account, for example `+15551234567`

The module generates a local `OPENCLAW_GATEWAY_TOKEN` at first boot in `/var/lib/openclaw/gateway-token` and passes it to the container through `/run/openclaw/openclaw.env`.

## Signal Setup

Use a dedicated Signal bot number if possible. OpenClaw upstream explicitly recommends this for "I text the bot and it replies" because running the bot on the same Signal account can trip loop protection.

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
