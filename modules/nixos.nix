{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.age;
  inherit (config) users;
  common = import ./common.nix { inherit pkgs lib; };

  options =
    lib.map (path: "identity=${path}") cfg.identityPaths
    ++ [
      "allow_other"
      "x-gvfs-hide"
    ]
    ++ lib.optional cfg.keepCached "keep_cached";

  secretSubmodule = lib.types.submodule (
    { config, name, ... }:
    {
      options = common.secretOpts { inherit common name; } // {
        owner = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.str lib.types.int);
          default = null;
          defaultText = "current group";
          example = "user";
          apply = common.tryMaybeGetId "UID" "user" users.users;
          description = ''
            User owner of the decrypted file at runtime. If null, defaults to the current user.
          '';
        };

        group = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.str lib.types.int);
          default = null;
          defaultText = "current group";
          example = "user";
          apply = common.tryMaybeGetId "GID" "group" users.groups;
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
  _class = "nixos";

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
    # TODO: figure out why it doesn't work without this, i swear i tried everything
    environment.systemPackages = [ cfg.package ];
    systemd = {
      automounts = lib.singleton {
        description = "Age Encrypted File System Automount Point";
        where = cfg.secretsDir;
        wantedBy = [ "sysinit.target" ];
      };
      mounts = lib.singleton {
        description = "Age Encrypted File System";
        what = toString cfg.metaFile;
        where = cfg.secretsDir;
        type = "fuse.agefs";
        options = lib.concatStringsSep "," options;
        mountConfig.Environment = "PATH=${
          lib.makeBinPath ([ cfg.package ] ++ cfg.pluginPackages)
        }:/run/wrappers/bin:/run/current-system/sw/bin";
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
