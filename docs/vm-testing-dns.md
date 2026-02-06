# VM Testing DNS Setup

When testing the VM locally, you need to configure DNS resolution for the `local.hobitin.eu` domain and its subdomains.

## Problem

The VM uses these domains:
- `local.hobitin.eu` (Homepage)
- `grafana.local.hobitin.eu` (Grafana)
- `metrics.local.hobitin.eu` (VictoriaMetrics)
- `logs.local.hobitin.eu` (Loki)

These need to resolve to `127.0.0.1` (or `localhost`) for local testing.

## Solution: /etc/hosts

Add these entries to `/etc/hosts`:

```bash
sudo tee -a /etc/hosts <<EOF
# Homelab VM testing
127.0.0.1 local.hobitin.eu
127.0.0.1 grafana.local.hobitin.eu
127.0.0.1 metrics.local.hobitin.eu
127.0.0.1 logs.local.hobitin.eu
EOF
```

## Verification

After adding the entries, test:

```bash
# Test DNS resolution
ping -c 1 local.hobitin.eu
ping -c 1 grafana.local.hobitin.eu

# Test services (VM must be running)
curl -k https://local.hobitin.eu:8443
curl -k https://grafana.local.hobitin.eu:8443
curl -k https://metrics.local.hobitin.eu:8443
curl -k https://logs.local.hobitin.eu:8443/ready
```

## Alternative: Host Header Testing

If you don't want to modify /etc/hosts, you can test using curl with Host headers:

```bash
curl -k -H "Host: grafana.local.hobitin.eu" https://local.hobitin.eu:8443
curl -k -H "Host: metrics.local.hobitin.eu" https://local.hobitin.eu:8443
curl -k -H "Host: logs.local.hobitin.eu" https://local.hobitin.eu:8443/ready
```

## Cleanup

To remove the entries from /etc/hosts when done testing:

```bash
sudo sed -i.bak '/# Homelab VM testing/,+4d' /etc/hosts
```

## Production Note

In production with Tailscale, you'll configure Cloudflare DNS to point:
- `*.home.hobitin.eu` → Tailscale IP (100.x.x.x)

This makes all services accessible remotely via proper DNS.
