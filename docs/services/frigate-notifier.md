# Frigate Notifier

Small systemd service that subscribes to Frigate MQTT events and sends filtered object notifications by email.

## Status

**Enabled:** Yes

Production sends email notifications to `jan@kaifer.cz` for `person` and `car` events from `camera2`. Emails include the existing Frigate event snapshot JPEG attachment plus a second `-bbox.jpg` attachment requested with Frigate's `bbox=1` overlay, with the latest camera frame as a fallback for either image.

Notifications are intentionally limited to Frigate `new` events. Car notifications also require Frigate to mark the object as active/non-stationary, which prevents a parked car from generating repeated overnight emails when it is re-detected.

## Configuration

**Module:** `modules/services/frigate-notifier.nix`  
**Pattern:** `homelab.services.frigate-notifier.enable`

Important options:

| Option | Default | Description |
|--------|---------|-------------|
| `recipient` | required | Destination email address |
| `labels` | `[ "person" "car" ]` | Object labels that trigger notifications |
| `eventTypes` | `[ "new" ]` | Frigate event types that trigger notifications |
| `activeOnlyLabels` | `[ "car" ]` | Labels that only notify while active/non-stationary |
| `cameras` | `[ "camera2" ]` | Cameras that trigger notifications |
| `topic` | `frigate/events` | Frigate MQTT event topic |
| `cooldownSeconds` | `300` | Per-event notification cooldown |
| `frigateApiUrl` | `http://127.0.0.1:5000` | Local Frigate API used for snapshot attachments |
| `mqttPasswordFile` | required | MQTT password file |
| `smtpEnvironmentFile` | required | SMTP credential environment file |

The bounding-box attachment is fetched from the same event snapshot endpoint with `bbox=1`. Frigate applies snapshot query parameters while an event is still in progress; production notifications currently subscribe only to `new` events so the annotated image is requested during that window.

Example production config:

```nix
homelab.services.frigate-notifier = {
  enable = true;
  recipient = "jan@kaifer.cz";
  mqttPasswordFile = config.age.secrets.mqtt-frigate-password.path;
  smtpEnvironmentFile = config.age.secrets.frigate-notifier-smtp-env.path;
};
```

## SMTP Secret

The production SMTP secret is `secrets/frigate-notifier-smtp-env.age`. The SMTP environment file should contain:

```env
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=notifier@example.com
SMTP_PASSWORD=change-me
SMTP_FROM=Frigate <notifier@example.com>
SMTP_ENVELOPE_FROM=notifier@example.com
SMTP_STARTTLS=true
```

Use `SMTP_SSL=true` and `SMTP_PORT=465` instead when the provider requires implicit TLS.
For Google Workspace SMTP relay with "Only registered Apps users", keep
`SMTP_ENVELOPE_FROM` set to the authenticated Workspace user even if the visible
`SMTP_FROM` display address is an alias-style notification address.

## Runtime

Check service status:

```bash
systemctl status frigate-notifier
```

Check logs:

```bash
journalctl -u frigate-notifier -n 200 --no-pager
```

## Dependencies

- Frigate MQTT publishing
- Mosquitto
- Working outbound SMTP credentials
