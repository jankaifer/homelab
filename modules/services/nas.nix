# NAS service layout and network file sharing for frame1
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.nas;

  sharePaths = {
    root = cfg.rootPath;
    media = "${cfg.rootPath}/media";
    mediaMovies = "${cfg.rootPath}/media/movies";
    mediaTv = "${cfg.rootPath}/media/tv";
    mediaMusic = "${cfg.rootPath}/media/music";
    mediaBooks = "${cfg.rootPath}/media/books";
    downloads = "${cfg.rootPath}/downloads";
    downloadsComplete = "${cfg.rootPath}/downloads/complete";
    downloadsIncomplete = "${cfg.rootPath}/downloads/incomplete";
    nvr = "${cfg.rootPath}/nvr";
    backups = "${cfg.rootPath}/backups";
    private = "${cfg.rootPath}/private";
  };

  trustedNetworks = [
    cfg.lanCidr
    cfg.tailscaleCidr
  ];

  exportTargets = lib.concatStringsSep " " trustedNetworks;

  mkShare = name: path: extra: {
    inherit path;
    browseable = "yes";
    "read only" = if extra.readOnly then "yes" else "no";
    "valid users" = extra.validUsers;
  } // lib.optionalAttrs (extra ? writeList) {
    "write list" = extra.writeList;
  } // lib.optionalAttrs (extra ? forceGroup) {
    "force group" = extra.forceGroup;
  } // {
    "create mask" = extra.createMask;
    "directory mask" = extra.directoryMask;
    "inherit permissions" = "yes";
    "inherit acls" = "no";
    "vfs objects" = "catia fruit streams_xattr";
    "fruit:metadata" = "stream";
    "fruit:resource" = "stream";
    "fruit:time machine" = "no";
  };
in
{
  options.homelab.services.nas = {
    enable = lib.mkEnableOption "local NAS layout with Samba and NFS";

    rootPath = lib.mkOption {
      type = lib.types.str;
      default = "/nas";
      description = "Root directory for NAS shares.";
    };

    lanCidr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.2.0/24";
      description = "Trusted LAN subnet for NFS exports.";
    };

    tailscaleCidr = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10";
      description = "Trusted Tailscale subnet for NFS exports.";
    };

    adminSmbPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the Samba password for the admin SMB user.";
    };

    guestSmbPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the Samba password for the guest SMB user.";
    };

    guestUser = lib.mkOption {
      type = lib.types.str;
      default = "nasguest";
      description = "Human guest NAS user.";
    };

    sharedGroup = lib.mkOption {
      type = lib.types.str;
      default = "nas-shared";
      description = "Shared group for media and service-oriented NAS paths.";
    };

    adminGroup = lib.mkOption {
      type = lib.types.str;
      default = "nas-admin";
      description = "Admin group for NAS-only private access.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.adminSmbPasswordFile != null;
        message = "homelab.services.nas.adminSmbPasswordFile must be set when NAS is enabled.";
      }
      {
        assertion = cfg.guestSmbPasswordFile != null;
        message = "homelab.services.nas.guestSmbPasswordFile must be set when NAS is enabled.";
      }
    ];

    users.groups.${cfg.sharedGroup} = { };
    users.groups.${cfg.adminGroup} = { };

    users.users.jankaifer.extraGroups = [ cfg.sharedGroup cfg.adminGroup ];

    users.users.${cfg.guestUser} = {
      isNormalUser = true;
      description = "Guest NAS user";
      home = "/var/empty";
      createHome = false;
      shell = "${pkgs.shadow}/bin/nologin";
    };

    systemd.tmpfiles.rules = [
      "d ${sharePaths.root} 0755 root root - -"
      "d ${sharePaths.media} 2775 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.mediaMovies} 2775 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.mediaTv} 2775 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.mediaMusic} 2775 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.mediaBooks} 2775 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.downloads} 2770 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.downloadsComplete} 2770 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.downloadsIncomplete} 2770 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.nvr} 2770 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.backups} 2770 jankaifer ${cfg.sharedGroup} - -"
      "d ${sharePaths.private} 0700 jankaifer ${cfg.adminGroup} - -"
    ];

    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "frame1 NAS";
          "hosts allow" = [ "192.168.2." "100." "127." ];
          "hosts deny" = [ "0.0.0.0/0" ];
          "map to guest" = "Never";
          "load printers" = "no";
          "printing" = "bsd";
          "disable spoolss" = "yes";
          "ea support" = "yes";
          "fruit:aapl" = "yes";
          "unix extensions" = "yes";
          "wide links" = "no";
        };

        media = mkShare "media" sharePaths.media {
          readOnly = true;
          validUsers = [ "jankaifer" cfg.guestUser "@${cfg.sharedGroup}" ];
          writeList = [ "jankaifer" "@${cfg.sharedGroup}" ];
          forceGroup = cfg.sharedGroup;
          createMask = "0664";
          directoryMask = "2775";
        };

        downloads = mkShare "downloads" sharePaths.downloads {
          readOnly = false;
          validUsers = [ "jankaifer" "@${cfg.sharedGroup}" ];
          writeList = [ "jankaifer" "@${cfg.sharedGroup}" ];
          forceGroup = cfg.sharedGroup;
          createMask = "0660";
          directoryMask = "2770";
        };

        nvr = mkShare "nvr" sharePaths.nvr {
          readOnly = false;
          validUsers = [ "jankaifer" "@${cfg.sharedGroup}" ];
          writeList = [ "jankaifer" "@${cfg.sharedGroup}" ];
          forceGroup = cfg.sharedGroup;
          createMask = "0660";
          directoryMask = "2770";
        };

        backups = mkShare "backups" sharePaths.backups {
          readOnly = false;
          validUsers = [ "jankaifer" "@${cfg.sharedGroup}" ];
          writeList = [ "jankaifer" "@${cfg.sharedGroup}" ];
          forceGroup = cfg.sharedGroup;
          createMask = "0660";
          directoryMask = "2770";
        };

        private = mkShare "private" sharePaths.private {
          readOnly = false;
          validUsers = [ "jankaifer" ];
          writeList = [ "jankaifer" ];
          forceGroup = cfg.adminGroup;
          createMask = "0600";
          directoryMask = "0700";
        };
      };
    };

    services.nfs.server = {
      enable = true;
      createMountPoints = true;
      mountdPort = 4002;
      lockdPort = 4001;
      statdPort = 4000;
      exports = ''
        ${sharePaths.media} ${cfg.lanCidr}(rw,sync,no_subtree_check,root_squash) ${cfg.tailscaleCidr}(rw,sync,no_subtree_check,root_squash)
        ${sharePaths.downloads} ${cfg.lanCidr}(rw,sync,no_subtree_check,root_squash) ${cfg.tailscaleCidr}(rw,sync,no_subtree_check,root_squash)
        ${sharePaths.nvr} ${cfg.lanCidr}(rw,sync,no_subtree_check,root_squash) ${cfg.tailscaleCidr}(rw,sync,no_subtree_check,root_squash)
        ${sharePaths.backups} ${cfg.lanCidr}(rw,sync,no_subtree_check,root_squash) ${cfg.tailscaleCidr}(rw,sync,no_subtree_check,root_squash)
        ${sharePaths.private} ${cfg.lanCidr}(rw,sync,no_subtree_check,root_squash) ${cfg.tailscaleCidr}(rw,sync,no_subtree_check,root_squash)
      '';
    };

    networking.firewall.allowedTCPPorts = [
      111
      2049
      4000
      4001
      4002
    ];
    networking.firewall.allowedUDPPorts = [
      111
      2049
      4000
      4001
      4002
    ];

    systemd.services.homelab-samba-users = {
      description = "Initialize Samba users for homelab NAS";
      after = [ "network.target" ];
      before = [
        "samba-smbd.service"
        "samba-nmbd.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.services.samba.package pkgs.shadow ];
      restartTriggers = [
        cfg.adminSmbPasswordFile
        cfg.guestSmbPasswordFile
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        printf '%s\n%s\n' "$(cat ${cfg.adminSmbPasswordFile})" "$(cat ${cfg.adminSmbPasswordFile})" | smbpasswd -s -a jankaifer >/dev/null
        printf '%s\n%s\n' "$(cat ${cfg.guestSmbPasswordFile})" "$(cat ${cfg.guestSmbPasswordFile})" | smbpasswd -s -a ${cfg.guestUser} >/dev/null
      '';
    };
  };
}
