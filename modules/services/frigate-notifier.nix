# Frigate event email notifier
#
# Consumes Frigate MQTT events and sends filtered object alerts via SMTP.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.frigate-notifier;
  python = pkgs.python3.withPackages (ps: [ ps.paho-mqtt ]);
  notifierScript = pkgs.writeText "frigate-email-notifier.py" ''
    import argparse
    import json
    import os
    import smtplib
    import ssl
    import time
    from email.message import EmailMessage

    import paho.mqtt.client as mqtt


    def env_bool(name, default):
        value = os.environ.get(name)
        if value is None:
            return default
        return value.lower() in ("1", "true", "yes", "on")


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
            smtp.send_message(message)


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument("--mqtt-host", required=True)
        parser.add_argument("--mqtt-port", type=int, required=True)
        parser.add_argument("--mqtt-user", required=True)
        parser.add_argument("--mqtt-password-file", required=True)
        parser.add_argument("--topic", required=True)
        parser.add_argument("--recipient", required=True)
        parser.add_argument("--labels", nargs="+", required=True)
        parser.add_argument("--cameras", nargs="+", required=True)
        parser.add_argument("--frigate-url", required=True)
        parser.add_argument("--cooldown-seconds", type=int, required=True)
        args = parser.parse_args()

        labels = set(args.labels)
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

                if event_type not in ("new", "update"):
                    return
                if label not in labels or camera not in cameras or not event_id:
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
            --cameras ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.cameras} \
            --frigate-url ${lib.escapeShellArg cfg.frigateUrl} \
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
