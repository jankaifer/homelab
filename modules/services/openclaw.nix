{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.openclaw;
  signalCfg = cfg.signal;

  defaultImage =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "ghcr.io/openclaw/openclaw:2026.4.29@sha256:c2d59c17dee1e87e60e09a58111efd51eff2e043dc0b1dc0c5456ebbb16a0199"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "ghcr.io/openclaw/openclaw:2026.4.29@sha256:a0c8cb7f5e7857b4f40c3ceaeb37ec89641a9f3991e66957849e4e3f8e8497a6"
    else
      "ghcr.io/openclaw/openclaw:2026.4.29";

  runtimeDir = "/run/openclaw";
  generatedEnvFile = "${runtimeDir}/openclaw.env";
  generatedConfigFile = "${cfg.dataDir}/openclaw.json";
  tokenFile = "${cfg.dataDir}/gateway-token";
  signalHttpUrl = "http://${signalCfg.httpHost}:${toString signalCfg.httpPort}";
  controlUiAllowedOrigins = [
    "http://127.0.0.1:${toString cfg.port}"
  ] ++ lib.optionals cfg.exposeUi.enable [
    "https://${cfg.exposeUi.domain}"
  ];
  gatewayTrustedProxies = [ "127.0.0.1" "::1" ];
  trustedProxyRequiredHeaders = [
    "remote-user"
    "remote-email"
    "x-forwarded-proto"
    "x-forwarded-host"
  ];
  trustedProxyAllowedUsers = [ "jan@kaifer.cz" ];
  defaultOpenRouterModel = "openrouter/moonshotai/kimi-k2.6";
  effectiveModel =
    if cfg.model != null then
      cfg.model
    else if cfg.openRouter.enable then
      cfg.openRouter.model
    else
      "";

  mkJsonList = values: builtins.toJSON values;
in
{
  options.homelab.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw personal assistant gateway";

    image = lib.mkOption {
      type = lib.types.str;
      default = defaultImage;
      defaultText = "OpenClaw 2026.4.29 pinned per target architecture";
      description = "OpenClaw OCI image. Defaults to the 2026.4.29 per-architecture image manifest digest.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Host-loopback OpenClaw gateway port.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw";
      description = "Persistent OpenClaw configuration and state directory.";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw/workspace";
      description = "Private OpenClaw workspace directory. No host home or repository paths are mounted.";
    };

    pluginRuntimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw/plugin-runtime-deps";
      description = "Persistent OpenClaw bundled-plugin runtime dependency cache.";
    };

    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw/cache";
      description = "Persistent OpenClaw container cache directory mounted at /home/node/.cache.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional agenix-managed env file passed to the gateway container.
        Use it for provider keys such as OPENROUTER_API_KEY or BRAVE_API_KEY.
      '';
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "openai/gpt-4.1-mini";
      description = "Optional default OpenClaw model identifier. Overrides openRouter.model when set.";
    };

    openRouter = {
      enable = lib.mkEnableOption "OpenRouter as the default OpenClaw model provider";

      model = lib.mkOption {
        type = lib.types.str;
        default = defaultOpenRouterModel;
        example = "openrouter/anthropic/claude-sonnet-4-5";
        description = "OpenRouter model reference used as OpenClaw's default primary model.";
      };
    };

    allowBrowserTool = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow the full browser automation tool. The default image is kept web-fetch/search only.";
    };

    exposeUi = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose the OpenClaw control UI through Caddy protected by Authelia forward-auth.";
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = "openclaw.frame1.hobitin.eu";
        description = "OpenClaw control UI domain when exposeUi.enable is true.";
      };
    };

    signal = {
      enable = lib.mkEnableOption "OpenClaw Signal channel through signal-cli";

      accountFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to a file containing the Signal bot account in E.164 format.";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/openclaw-signal";
        description = "Persistent signal-cli state directory.";
      };

      httpHost = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "signal-cli daemon HTTP bind host.";
      };

      httpPort = lib.mkOption {
        type = lib.types.port;
        default = 18080;
        description = "signal-cli daemon HTTP port.";
      };

      dmPolicy = lib.mkOption {
        type = lib.types.enum [ "pairing" "allowlist" "disabled" ];
        default = "pairing";
        description = "Signal DM access policy. The initial safe default requires pairing approval.";
      };

      allowFrom = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Optional Signal DM allowlist of E.164 numbers or uuid:<id> values.";
      };

      groupPolicy = lib.mkOption {
        type = lib.types.enum [ "allowlist" "disabled" ];
        default = "disabled";
        description = "Signal group policy. Groups are disabled for the first deployment.";
      };

      mediaMaxMb = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "Maximum Signal media attachment size accepted by OpenClaw.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = signalCfg.enable -> signalCfg.accountFile != null;
        message = "homelab.services.openclaw.signal.accountFile must be set when Signal is enabled.";
      }
      {
        assertion = cfg.exposeUi.enable -> config.homelab.services.caddy.enable;
        message = "homelab.services.openclaw.exposeUi requires homelab.services.caddy.enable.";
      }
      {
        assertion = cfg.exposeUi.enable -> config.homelab.services.authelia.enable;
        message = "homelab.services.openclaw.exposeUi requires homelab.services.authelia.enable.";
      }
      {
        assertion = cfg.openRouter.enable -> cfg.environmentFile != null;
        message = "homelab.services.openclaw.openRouter.enable requires environmentFile with OPENROUTER_API_KEY.";
      }
    ];

    users.groups.openclaw-signal = lib.mkIf signalCfg.enable { };
    users.users.openclaw-signal = lib.mkIf signalCfg.enable {
      isSystemUser = true;
      group = "openclaw-signal";
      home = signalCfg.dataDir;
      createHome = true;
    };

    environment.systemPackages = lib.mkIf signalCfg.enable [
      pkgs.signal-cli
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 1000 1000 - -"
      "d ${cfg.workspaceDir} 0700 1000 1000 - -"
      "d ${cfg.pluginRuntimeDir} 0700 1000 1000 - -"
      "d ${cfg.cacheDir} 0700 1000 1000 - -"
      "d ${runtimeDir} 0700 root root - -"
    ] ++ lib.optionals signalCfg.enable [
      "d ${signalCfg.dataDir} 0700 openclaw-signal openclaw-signal - -"
    ];

    systemd.services.openclaw-bootstrap = {
      description = "Prepare OpenClaw runtime configuration";
      before = [ "podman-openclaw.service" ];
      requiredBy = [ "podman-openclaw.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      path = [ pkgs.coreutils pkgs.gnused pkgs.jq pkgs.openssl ];
      script = ''
        set -euo pipefail

        install -d -m 0700 -o 1000 -g 1000 ${lib.escapeShellArg cfg.dataDir}
        install -d -m 0700 -o 1000 -g 1000 ${lib.escapeShellArg cfg.workspaceDir}
        install -d -m 0700 -o 1000 -g 1000 ${lib.escapeShellArg cfg.pluginRuntimeDir}
        install -d -m 0700 ${lib.escapeShellArg runtimeDir}

        if [ ! -s ${lib.escapeShellArg tokenFile} ]; then
          umask 077
          openssl rand -base64 48 > ${lib.escapeShellArg tokenFile}
          chown root:root ${lib.escapeShellArg tokenFile}
          chmod 0400 ${lib.escapeShellArg tokenFile}
        fi

        ${if cfg.environmentFile == null then ''
          : > ${lib.escapeShellArg generatedEnvFile}
        '' else ''
          sed '/^[[:space:]]*OPENCLAW_GATEWAY_TOKEN=/d' ${lib.escapeShellArg cfg.environmentFile} > ${lib.escapeShellArg generatedEnvFile}
        ''}
        chmod 0400 ${lib.escapeShellArg generatedEnvFile}

        signal_account=""
        ${lib.optionalString signalCfg.enable ''
          signal_account="$(tr -d '\n' < ${lib.escapeShellArg signalCfg.accountFile})"
        ''}

        jq -n \
          --arg model ${lib.escapeShellArg effectiveModel} \
          --argjson signalEnabled ${if signalCfg.enable then "true" else "false"} \
          --arg signalAccount "$signal_account" \
          --arg signalHttpUrl ${lib.escapeShellArg signalHttpUrl} \
          --arg signalDmPolicy ${lib.escapeShellArg signalCfg.dmPolicy} \
          --arg signalGroupPolicy ${lib.escapeShellArg signalCfg.groupPolicy} \
          --argjson signalAllowFrom ${lib.escapeShellArg (mkJsonList signalCfg.allowFrom)} \
          --argjson signalMediaMaxMb ${toString signalCfg.mediaMaxMb} \
          --argjson controlUiAllowedOrigins ${lib.escapeShellArg (mkJsonList controlUiAllowedOrigins)} \
          --argjson gatewayTrustedProxies ${lib.escapeShellArg (mkJsonList gatewayTrustedProxies)} \
          --argjson trustedProxyRequiredHeaders ${lib.escapeShellArg (mkJsonList trustedProxyRequiredHeaders)} \
          --argjson trustedProxyAllowedUsers ${lib.escapeShellArg (mkJsonList trustedProxyAllowedUsers)} \
          --argjson toolAllow ${lib.escapeShellArg (mkJsonList (
            [ "group:web" "message" "session_status" ]
            ++ lib.optionals cfg.allowBrowserTool [ "browser" ]
          ))} \
          --argjson toolDeny ${lib.escapeShellArg (mkJsonList (
            [ "group:runtime" "group:fs" "group:automation" "group:nodes" "group:media" ]
            ++ lib.optionals (!cfg.allowBrowserTool) [ "group:ui" ]
          ))} \
          '
          {
            gateway: {
              mode: "local",
              bind: "loopback",
              trustedProxies: $gatewayTrustedProxies,
              auth: {
                mode: "trusted-proxy",
                trustedProxy: {
                  userHeader: "remote-email",
                  requiredHeaders: $trustedProxyRequiredHeaders,
                  allowUsers: $trustedProxyAllowedUsers,
                  allowLoopback: true
                }
              },
              controlUi: {
                allowedOrigins: $controlUiAllowedOrigins
              }
            },
            tools: {
              profile: "full",
              allow: $toolAllow,
              deny: $toolDeny
            },
            browser: {
              enabled: false
            },
            session: {
              dmScope: "per-channel-peer"
            },
            messages: {
              visibleReplies: "message_tool"
            },
            channels: (
              if $signalEnabled then {
                signal: {
                  enabled: true,
                  account: $signalAccount,
                  httpUrl: $signalHttpUrl,
                  autoStart: false,
                  dmPolicy: $signalDmPolicy,
                  allowFrom: $signalAllowFrom,
                  groupPolicy: $signalGroupPolicy,
                  configWrites: false,
                  ignoreAttachments: true,
                  ignoreStories: true,
                  sendReadReceipts: false,
                  mediaMaxMb: $signalMediaMaxMb
                }
              } else {} end
            )
          }
          + (if $model == "" then {} else {
            agents: {
              defaults: {
                model: {
                  primary: $model
                }
              }
            }
          } end)
          ' > ${lib.escapeShellArg "${runtimeDir}/openclaw.desired.json"}

        if [ -s ${lib.escapeShellArg generatedConfigFile} ] && jq -e '.meta.lastTouchedVersion?' ${lib.escapeShellArg generatedConfigFile} >/dev/null; then
          jq -s '.[1] + { meta: .[0].meta }' \
            ${lib.escapeShellArg generatedConfigFile} \
            ${lib.escapeShellArg "${runtimeDir}/openclaw.desired.json"} \
            > ${lib.escapeShellArg "${runtimeDir}/openclaw.json.new"}
        else
          cp ${lib.escapeShellArg "${runtimeDir}/openclaw.desired.json"} ${lib.escapeShellArg "${runtimeDir}/openclaw.json.new"}
        fi

        mv ${lib.escapeShellArg "${runtimeDir}/openclaw.json.new"} ${lib.escapeShellArg generatedConfigFile}

        chown 1000:1000 ${lib.escapeShellArg generatedConfigFile}
        chmod 0600 ${lib.escapeShellArg generatedConfigFile}
      '';
    };

    systemd.services.openclaw-signal = lib.mkIf signalCfg.enable {
      description = "signal-cli daemon for OpenClaw";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      before = [ "podman-openclaw.service" ];
      serviceConfig = {
        User = "openclaw-signal";
        Group = "openclaw-signal";
        WorkingDirectory = signalCfg.dataDir;
        StateDirectory = "openclaw-signal";
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 10;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ signalCfg.dataDir ];
      };
      path = [ pkgs.coreutils pkgs.signal-cli ];
      script = ''
        set -euo pipefail

        account="$(tr -d '\n' < ${lib.escapeShellArg signalCfg.accountFile})"
        exec signal-cli \
          --config ${lib.escapeShellArg signalCfg.dataDir} \
          --account "$account" \
          daemon \
          --http ${lib.escapeShellArg signalCfg.httpHost}:${toString signalCfg.httpPort}
      '';
    };

    virtualisation.oci-containers.containers.openclaw = {
      image = cfg.image;
      autoStart = true;
      autoRemoveOnStop = false;
      pull = "missing";
      cmd = [
        "node"
        "openclaw.mjs"
        "gateway"
        "--bind"
        "loopback"
        "--port"
        (toString cfg.port)
        "--allow-unconfigured"
      ];
      volumes = [
        "${cfg.dataDir}:/home/node/.openclaw:rw"
        "${cfg.workspaceDir}:/home/node/.openclaw/workspace:rw"
        "${cfg.pluginRuntimeDir}:/var/lib/openclaw/plugin-runtime-deps:rw"
        "${cfg.cacheDir}:/home/node/.cache:rw"
      ];
      environment = {
        HOME = "/home/node";
        TZ = config.time.timeZone;
        OPENCLAW_DISABLE_BONJOUR = "1";
        OPENCLAW_GATEWAY_PORT = toString cfg.port;
        OPENCLAW_PLUGIN_STAGE_DIR = "/var/lib/openclaw/plugin-runtime-deps";
      };
      extraOptions = [
        "--network=host"
        "--env-file=${generatedEnvFile}"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--read-only"
        "--tmpfs=/tmp:rw,nosuid,nodev,noexec,size=256m"
        "--pids-limit=512"
        "--memory=3g"
        "--cpus=2"
        "--restart=unless-stopped"
      ];
    };

    systemd.services.podman-openclaw = {
      after = [
        "network-online.target"
        "openclaw-bootstrap.service"
      ] ++ lib.optionals signalCfg.enable [
        "openclaw-signal.service"
      ];
      wants = [
        "network-online.target"
        "openclaw-bootstrap.service"
      ] ++ lib.optionals signalCfg.enable [
        "openclaw-signal.service"
      ];
      restartTriggers = [
        config.systemd.services.openclaw-bootstrap.script
      ];
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = 10;
      };
    };

    homelab.services.caddy.protectedVirtualHosts = lib.mkIf cfg.exposeUi.enable {
      ${cfg.exposeUi.domain} = {
        upstream = "127.0.0.1:${toString cfg.port}";
        extraConfig = ''
          request_header X-OpenClaw-Scopes "operator.admin,operator.write,operator.read"
        '';
      };
    };
  };
}
