# Authelia identity and SSO module
#
# Provides a single lightweight authentication portal and OIDC provider for
# homelab services. Secrets and the users database are supplied through agenix.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.authelia;
  stateDir = "/var/lib/authelia-main";
  authUrl = "https://${cfg.domain}";
  redirectUrl = "https://${cfg.defaultRedirectDomain}";
in
{
  options.homelab.services.authelia = {
    enable = lib.mkEnableOption "Authelia SSO";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "auth.frame1.hobitin.eu";
      description = "Authelia portal domain exposed through Caddy";
    };

    cookieDomain = lib.mkOption {
      type = lib.types.str;
      default = "frame1.hobitin.eu";
      description = "Cookie domain Authelia uses for protected services";
    };

    defaultRedirectDomain = lib.mkOption {
      type = lib.types.str;
      default = "frame1.hobitin.eu";
      description = "Default URL target when users visit the Authelia portal directly";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "Internal Authelia HTTP port";
    };

    usersFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the agenix-managed Authelia users database";
    };

    secrets = {
      jwtSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to Authelia JWT secret file";
      };

      sessionSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to Authelia session secret file";
      };

      storageEncryptionKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to Authelia storage encryption key file";
      };

      oidcHmacSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to Authelia OIDC HMAC secret file";
      };

      oidcIssuerPrivateKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to Authelia OIDC issuer private key file";
      };
    };

    grafana = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Register a Grafana OIDC client in Authelia";
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = config.homelab.services.grafana.domain;
        defaultText = "config.homelab.services.grafana.domain";
        description = "Grafana domain used in the OIDC redirect URI";
      };

      clientSecretDigest = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PBKDF2 digest of the Grafana OIDC client secret";
      };
    };

    accessControlRules = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [
        {
          domain = "auth.frame1.hobitin.eu";
          policy = "bypass";
        }
        {
          domain = "*.frame1.hobitin.eu";
          policy = "one_factor";
        }
      ];
      description = "Authelia access-control rules for forward-auth protected services";
    };

    metrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose Authelia metrics on loopback";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9959;
        description = "Internal Authelia metrics port";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.usersFile != null;
        message = "homelab.services.authelia.usersFile must point at an agenix-managed users database";
      }
      {
        assertion =
          cfg.secrets.jwtSecretFile != null
          && cfg.secrets.sessionSecretFile != null
          && cfg.secrets.storageEncryptionKeyFile != null
          && cfg.secrets.oidcHmacSecretFile != null
          && cfg.secrets.oidcIssuerPrivateKeyFile != null;
        message = "homelab.services.authelia.secrets must include JWT, session, storage, OIDC HMAC, and OIDC issuer key files";
      }
      {
        assertion = (!cfg.grafana.enable) || cfg.grafana.clientSecretDigest != null;
        message = "homelab.services.authelia.grafana.clientSecretDigest is required when the Grafana OIDC client is enabled";
      }
    ];

    services.authelia.instances.main = {
      enable = true;
      package = pkgs.authelia;

      secrets = {
        jwtSecretFile = cfg.secrets.jwtSecretFile;
        sessionSecretFile = cfg.secrets.sessionSecretFile;
        storageEncryptionKeyFile = cfg.secrets.storageEncryptionKeyFile;
        oidcHmacSecretFile = cfg.secrets.oidcHmacSecretFile;
        oidcIssuerPrivateKeyFile = cfg.secrets.oidcIssuerPrivateKeyFile;
      };

      settings = {
        theme = "auto";
        default_2fa_method = "";

        server = {
          address = "tcp://127.0.0.1:${toString cfg.port}/";
          endpoints.authz."forward-auth".implementation = "ForwardAuth";
        };

        log = {
          level = "info";
          format = "json";
        };

        telemetry.metrics = {
          enabled = cfg.metrics.enable;
          address = "tcp://127.0.0.1:${toString cfg.metrics.port}";
        };

        authentication_backend = {
          file = {
            path = cfg.usersFile;
            watch = false;
            search = {
              email = true;
              case_insensitive = true;
            };
            password = {
              algorithm = "argon2";
              argon2 = {
                variant = "argon2id";
                iterations = 3;
                memory = 65536;
                parallelism = 4;
                key_length = 32;
                salt_length = 16;
              };
            };
          };
        };

        access_control = {
          default_policy = "deny";
          rules = cfg.accessControlRules;
        };

        session = {
          name = "authelia_session";
          same_site = "lax";
          inactivity = "15m";
          expiration = "8h";
          remember_me = "14d";
          cookies = [{
            domain = cfg.cookieDomain;
            authelia_url = authUrl;
            default_redirection_url = redirectUrl;
          }];
        };

        regulation = {
          max_retries = 5;
          find_time = "2m";
          ban_time = "15m";
        };

        storage.local.path = "${stateDir}/db.sqlite3";

        notifier.filesystem.filename = "${stateDir}/notification.txt";

        identity_providers.oidc = {
          enable_client_debug_messages = false;
          claims_policies.grafana.id_token = [ "email" "name" "groups" "preferred_username" ];
          clients = lib.optionals cfg.grafana.enable [{
            client_id = "grafana";
            client_name = "Grafana";
            client_secret = cfg.grafana.clientSecretDigest;
            public = false;
            authorization_policy = "one_factor";
            require_pkce = true;
            pkce_challenge_method = "S256";
            redirect_uris = [ "https://${cfg.grafana.domain}/login/generic_oauth" ];
            scopes = [ "openid" "profile" "groups" "email" ];
            response_types = [ "code" ];
            grant_types = [ "authorization_code" ];
            access_token_signed_response_alg = "none";
            userinfo_signed_response_alg = "none";
            token_endpoint_auth_method = "client_secret_basic";
            claims_policy = "grafana";
          }];
        };
      };
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy 127.0.0.1:${toString cfg.port}";

    homelab.prometheus.scrapeConfigs = lib.mkIf cfg.metrics.enable [
      {
        job_name = "authelia";
        static_configs = [{
          targets = [ "127.0.0.1:${toString cfg.metrics.port}" ];
          labels.instance = config.networking.hostName;
        }];
      }
    ];

    homelab.homepage.services = [{
      name = "Authelia";
      category = "Identity";
      description = "SSO and access control";
      href = authUrl;
      icon = "authelia";
    }];
  };
}
