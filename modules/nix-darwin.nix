{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.age;
  common = import ./common.nix { inherit pkgs lib; };

  options = lib.map (path: "identity=${path}") cfg.identityPaths ++ [
    "allow_other"
    "nobrowse"
  ];

  args = [
    (lib.getExe cfg.package)
    "-o"
    (lib.concatStringsSep "," options)
    "-f"
    cfg.metaFile
    cfg.secretsDir
  ];

  secretSubmodule = lib.types.submodule (
    { config, name, ... }:
    {
      options = common.secretOpts { inherit common name; } // {
        owner = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.str lib.types.int);
          default = null;
          defaultText = "current group";
          example = "user";
          apply = common.tryMaybeGetId "UID" "user" config.users.users;
          description = ''
            User owner of the decrypted file at runtime. If null, defaults to the current user.
          '';
        };

        group = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.str lib.types.int);
          default = null;
          defaultText = "current group";
          example = "user";
          apply = common.tryMaybeGetId "GID" "group" config.users.groups;
          description = ''
            Group owner of the decrypted file at runtime. If null, defaults to the current group.
          '';
        };
      };
      config.path = "${cfg.secretsDir}/${config.name}";
    }
  );
in

{
  _class = "darwin";

  options.age = common.rootOptions cfg // {
    secretsDir = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix";
      description = ''
        The location where agefs is mounted.
      '';
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf secretSubmodule;
      default = { };
      description = ''
        The secrets to decrypt upon access at runtime.
      '';
    };
  };

  config = lib.mkIf (cfg.secrets != { }) {
    launchd.daemons.agefs = {
      path = cfg.pluginPackages;
      command = lib.escapeShellArgs args;
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
      };
    };

    system.activationScripts = lib.mkIf cfg.wait {
      launchd.text = lib.mkAfter ''
        if [[ ! -e "${cfg.secretsDir}/.agefs" ]]; then
          /sbin/umount "${cfg.secretsDir}" > /dev/null || true
          /bin/launchctl kickstart -k system/${config.launchd.labelPrefix}.agefs
          echo "waiting for agefs..."
          /bin/wait4path "${cfg.secretsDir}"/.agefs
        fi
      '';
    };
  };
}
