# Frigate event email notifier
#
# Consumes Frigate MQTT events and sends filtered object alerts via SMTP.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.frigate-notifier;
  python = pkgs.python3.withPackages (ps: [ ps.paho-mqtt ps.pillow ]);
  notifierScript = pkgs.writeText "frigate-email-notifier.py" ''
    import argparse
    import io
    import json
    import os
    import smtplib
    import ssl
    import time
    from email.message import EmailMessage
    from urllib.error import URLError
    from urllib.request import urlopen

    import paho.mqtt.client as mqtt
    from PIL import Image, ImageDraw, ImageFont


    def env_bool(name, default):
        value = os.environ.get(name)
        if value is None:
            return default
        return value.lower() in ("1", "true", "yes", "on")


    def fetch_snapshot(args, camera, event_id):
        urls = [
            f"{args.frigate_api_url}/api/events/{event_id}/snapshot.jpg",
            f"{args.frigate_api_url}/api/{camera}/latest.jpg",
        ]

        for attempt in range(args.snapshot_attempts):
            for url in urls:
                try:
                    with urlopen(url, timeout=args.snapshot_timeout) as response:
                        content_type = response.headers.get("content-type", "")
                        if response.status == 200 and content_type.startswith("image/"):
                            return response.read()
                except URLError:
                    pass
            if attempt + 1 < args.snapshot_attempts:
                time.sleep(args.snapshot_retry_seconds)

        return None


    def object_text(label, score):
        if isinstance(score, (int, float)):
            return f"{label.upper()} {score:.0%}"
        return label.upper()


    def draw_label(draw, xy, text, font):
        left, top = xy
        padding_x = 12
        padding_y = 8
        text_box = draw.textbbox((0, 0), text, font=font)
        width = text_box[2] - text_box[0]
        height = text_box[3] - text_box[1]
        draw.rectangle(
            [
                left,
                top,
                left + width + padding_x * 2,
                top + height + padding_y * 2,
            ],
            fill=(220, 0, 0),
        )
        draw.text(
            (left + padding_x, top + padding_y),
            text,
            fill=(255, 255, 255),
            font=font,
        )


    def annotated_snapshot(snapshot, after, label, score):
        image = Image.open(io.BytesIO(snapshot)).convert("RGB")
        draw = ImageDraw.Draw(image)
        font_size = max(24, image.height // 24)
        font = ImageFont.load_default(size=font_size)
        border_width = max(12, min(image.size) // 45)
        text = object_text(label, score)

        box = after.get("box")
        if (
            isinstance(box, list)
            and len(box) == 4
            and all(isinstance(value, (int, float)) for value in box)
        ):
            x1, y1, x2, y2 = box
            x1 = max(0, min(image.width - 1, int(round(x1))))
            y1 = max(0, min(image.height - 1, int(round(y1))))
            x2 = max(0, min(image.width - 1, int(round(x2))))
            y2 = max(0, min(image.height - 1, int(round(y2))))
            if x2 <= x1 or y2 <= y1:
                x1, y1 = border_width, border_width
                x2, y2 = image.width - border_width, image.height - border_width
                text = f"{text} DETECTED"
        else:
            x1, y1 = border_width, border_width
            x2, y2 = image.width - border_width, image.height - border_width
            text = f"{text} DETECTED"

        for offset in range(border_width):
            draw.rectangle(
                [x1 - offset, y1 - offset, x2 + offset, y2 + offset],
                outline=(255, 0, 0),
            )

        label_top = max(0, y1 - border_width - font_size - 24)
        draw_label(draw, (max(0, x1), label_top), text, font)

        output = io.BytesIO()
        image.save(output, format="JPEG", quality=92)
        return output.getvalue()


    def send_email(args, event):
        after = event.get("after") or {}
        label = after.get("label", "object")
        camera = after.get("camera", "camera")
        event_id = after.get("id", "unknown")
        score = after.get("top_score") or after.get("score")
        score_text = f" ({score:.0%})" if isinstance(score, (int, float)) else ""

        message = EmailMessage()
        message["Subject"] = f"Frigate {label} detected on {camera}{score_text}"
        message["From"] = os.environ["SMTP_FROM"]
        message["To"] = args.recipient
        message.set_content(
            "\n".join(
                [
                    f"Frigate detected {label} on {camera}.",
                    f"Event ID: {event_id}",
                    f"Type: {event.get('type', 'unknown')}",
                    f"Score: {score_text.strip() or 'unknown'}",
                    f"Review: {args.frigate_url}/review?id={event_id}",
                ]
            )
        )

        snapshot = fetch_snapshot(args, camera, event_id)
        if snapshot is not None:
            message.add_attachment(
                snapshot,
                maintype="image",
                subtype="jpeg",
                filename=f"{camera}-{event_id}.jpg",
            )
            has_snapshot = True
        else:
            print(f"snapshot unavailable for event {event_id}", flush=True)
            has_snapshot = False

        if snapshot is not None:
            annotated = annotated_snapshot(snapshot, after, label, score)
            message.add_attachment(
                annotated,
                maintype="image",
                subtype="jpeg",
                filename=f"{camera}-{event_id}-annotated.jpg",
            )
            has_annotated_snapshot = True
        else:
            has_annotated_snapshot = False

        host = os.environ["SMTP_HOST"]
        port = int(os.environ.get("SMTP_PORT", "587"))
        username = os.environ.get("SMTP_USERNAME")
        password = os.environ.get("SMTP_PASSWORD")
        use_ssl = env_bool("SMTP_SSL", False)
        use_starttls = env_bool("SMTP_STARTTLS", not use_ssl)

        if use_ssl:
            smtp = smtplib.SMTP_SSL(host, port, timeout=20, context=ssl.create_default_context())
        else:
            smtp = smtplib.SMTP(host, port, timeout=20)

        with smtp:
            smtp.ehlo()
            if use_starttls:
                smtp.starttls(context=ssl.create_default_context())
                smtp.ehlo()
            if username:
                smtp.login(username, password or "")
            envelope_from = os.environ.get("SMTP_ENVELOPE_FROM") or username or os.environ["SMTP_FROM"]
            smtp.send_message(message, from_addr=envelope_from, to_addrs=[args.recipient])

        print(
            f"sent {label} notification for {camera} event {event_id} "
            f"to {args.recipient} snapshot={has_snapshot} "
            f"annotated_snapshot={has_annotated_snapshot}",
            flush=True,
        )


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument("--mqtt-host", required=True)
        parser.add_argument("--mqtt-port", type=int, required=True)
        parser.add_argument("--mqtt-user", required=True)
        parser.add_argument("--mqtt-password-file", required=True)
        parser.add_argument("--topic", required=True)
        parser.add_argument("--recipient", required=True)
        parser.add_argument("--labels", nargs="+", required=True)
        parser.add_argument("--event-types", nargs="+", required=True)
        parser.add_argument("--active-only-labels", nargs="*", default=[])
        parser.add_argument("--cameras", nargs="+", required=True)
        parser.add_argument("--frigate-url", required=True)
        parser.add_argument("--frigate-api-url", required=True)
        parser.add_argument("--snapshot-attempts", type=int, required=True)
        parser.add_argument("--snapshot-timeout", type=int, required=True)
        parser.add_argument("--snapshot-retry-seconds", type=int, required=True)
        parser.add_argument("--cooldown-seconds", type=int, required=True)
        args = parser.parse_args()

        labels = set(args.labels)
        event_types = set(args.event_types)
        active_only_labels = set(args.active_only_labels)
        cameras = set(args.cameras)
        last_sent = {}

        with open(args.mqtt_password_file, encoding="utf-8") as password_file:
            mqtt_password = password_file.read().strip()

        def on_connect(client, userdata, flags, reason_code, properties=None):
            if reason_code == 0:
                client.subscribe(args.topic)
            else:
                raise RuntimeError(f"MQTT connection failed with reason code {reason_code}")

        def on_message(client, userdata, msg):
            try:
                event = json.loads(msg.payload.decode("utf-8"))
                after = event.get("after") or {}
                event_type = event.get("type")
                label = after.get("label")
                camera = after.get("camera")
                event_id = after.get("id")

                if event_type not in event_types:
                    return
                if label not in labels or camera not in cameras or not event_id:
                    return
                if label in active_only_labels and not after.get("active", False):
                    print(
                        f"skipped inactive {label} event {event_id} on {camera}",
                        flush=True,
                    )
                    return

                key = (camera, label, event_id)
                now = time.monotonic()
                if now - last_sent.get(key, 0) < args.cooldown_seconds:
                    return

                send_email(args, event)
                last_sent[key] = now
            except Exception as exc:
                print(f"failed to process MQTT event: {exc}", flush=True)

        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        client.username_pw_set(args.mqtt_user, mqtt_password)
        client.on_connect = on_connect
        client.on_message = on_message
        client.connect(args.mqtt_host, args.mqtt_port, keepalive=60)
        client.loop_forever()


    if __name__ == "__main__":
        main()
  '';
in
{
  options.homelab.services.frigate-notifier = {
    enable = lib.mkEnableOption "Frigate MQTT event email notifications";

    mqttHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "MQTT broker hostname.";
    };

    mqttPort = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "MQTT broker port.";
    };

    mqttUser = lib.mkOption {
      type = lib.types.str;
      default = "frigate";
      description = "MQTT username used to read Frigate events.";
    };

    mqttPasswordFile = lib.mkOption {
      type = lib.types.str;
      description = "File containing the MQTT password.";
    };

    smtpEnvironmentFile = lib.mkOption {
      type = lib.types.str;
      description = "Environment file containing SMTP_HOST, SMTP_FROM, and optional SMTP_* settings.";
    };

    recipient = lib.mkOption {
      type = lib.types.str;
      description = "Email recipient for Frigate notifications.";
    };

    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "person" "car" ];
      description = "Frigate object labels that should trigger email notifications.";
    };

    eventTypes = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "new" "update" "end" ]);
      default = [ "new" ];
      description = "Frigate event types that should trigger email notifications.";
    };

    activeOnlyLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "car" ];
      description = "Labels that should only notify when Frigate marks the object active/non-stationary.";
    };

    cameras = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "camera2" ];
      description = "Frigate cameras that should trigger email notifications.";
    };

    topic = lib.mkOption {
      type = lib.types.str;
      default = "frigate/events";
      description = "MQTT topic used by Frigate events.";
    };

    frigateUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://frigate.frame1.hobitin.eu";
      description = "External Frigate URL included in notification emails.";
    };

    frigateApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:5000";
      description = "Local Frigate API URL used to fetch event snapshots.";
    };

    snapshotAttempts = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "How many times to try fetching an event snapshot before sending without it.";
    };

    snapshotTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "HTTP timeout for each snapshot fetch attempt.";
    };

    snapshotRetrySeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Delay between snapshot fetch attempts.";
    };

    cooldownSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Minimum seconds between repeated notifications for the same event.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.frigate-notifier = {
      description = "Frigate email notifications";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "mosquitto.service" "frigate.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "frigate";
        Group = "frigate";
        EnvironmentFile = cfg.smtpEnvironmentFile;
        ExecStart = ''
          ${python}/bin/python ${notifierScript} \
            --mqtt-host ${lib.escapeShellArg cfg.mqttHost} \
            --mqtt-port ${toString cfg.mqttPort} \
            --mqtt-user ${lib.escapeShellArg cfg.mqttUser} \
            --mqtt-password-file ${lib.escapeShellArg cfg.mqttPasswordFile} \
            --topic ${lib.escapeShellArg cfg.topic} \
            --recipient ${lib.escapeShellArg cfg.recipient} \
            --labels ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.labels} \
            --event-types ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.eventTypes} \
            --active-only-labels ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.activeOnlyLabels} \
            --cameras ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.cameras} \
            --frigate-url ${lib.escapeShellArg cfg.frigateUrl} \
            --frigate-api-url ${lib.escapeShellArg cfg.frigateApiUrl} \
            --snapshot-attempts ${toString cfg.snapshotAttempts} \
            --snapshot-timeout ${toString cfg.snapshotTimeoutSeconds} \
            --snapshot-retry-seconds ${toString cfg.snapshotRetrySeconds} \
            --cooldown-seconds ${toString cfg.cooldownSeconds}
        '';
        Restart = "always";
        RestartSec = 10;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
