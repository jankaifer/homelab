# Certificate Monitoring

Certificate expiry and renewal visibility for both Caddy-managed web certificates and the Mosquitto MQTT certificate.

## Status

**Enabled:** Yes on `frame1`, disabled in `frame1-vm`

## Configuration

**Module:** `modules/services/cert-monitoring.nix`
**Pattern:** `homelab.services.certMonitoring.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.certMonitoring.enable` | bool | false | Enable certificate health metrics |
| `homelab.services.certMonitoring.warningDays` | int | 14 | Days-before-expiry warning threshold |
| `homelab.services.certMonitoring.interval` | string | `15m` | Refresh interval for metric collection |
| `homelab.services.certMonitoring.textfileDir` | string | `/var/lib/node-exporter-textfile` | Node exporter textfile collector directory |

**Current configuration:**
```nix
homelab.services.certMonitoring = {
  enable = true;
  warningDays = 14;
  # interval = "15m";
};
```

## What It Monitors

- Certificate presence on disk
- Days until expiry
- Whether a certificate is inside the 14-day warning horizon
- Last observed result of the corresponding ACME renewal unit
- Last observed renewal-unit exit timestamp

Covered certificate paths:

- All current `homelab.services.caddy.virtualHosts`
- `mqtt.frame1.hobitin.eu`

## Data Flow

1. `homelab-certificate-metrics.service` inspects certificate files and systemd renewal units
2. Metrics are written into node exporter's textfile collector directory
3. `node_exporter` exposes the metrics
4. VictoriaMetrics scrapes the existing node exporter target
5. Grafana provisions a `Certificate Health` dashboard automatically

## Metrics

- `homelab_certificate_present`
- `homelab_certificate_days_until_expiry`
- `homelab_certificate_expiring_soon`
- `homelab_certificate_renewal_unit_result`
- `homelab_certificate_renewal_unit_last_exit_timestamp_seconds`

## Access

- **Grafana dashboard:** `Certificate Health`
- **VM testing:** disabled, because the VM uses Caddy local TLS instead of ACME

## Troubleshooting

Refresh metrics manually:
```bash
sudo systemctl start homelab-certificate-metrics.service
```

Inspect the generated Prometheus file:
```bash
sudo cat /var/lib/node-exporter-textfile/homelab-certificates.prom
```

Check the collector logs:
```bash
journalctl -u homelab-certificate-metrics -n 200 --no-pager
```

Verify the renewal unit status:
```bash
systemctl show acme-order-renew-frame1.hobitin.eu.service --property=Result --property=ExecMainExitTimestamp
```
