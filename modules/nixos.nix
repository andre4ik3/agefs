{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.age;
  common = import ./common.nix { inherit pkgs lib; };

  options = lib.map (path: "identity=${path}") cfg.identityPaths ++ [ "x-gvfs-hide" ];

  secretSubmodule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          example = "hello-world/my-secret";
          description = ''
            Relative path where the secret is made available.
          '';
        };

        file = lib.mkOption {
          type = lib.types.path;
          description = ''
            The encrypted age file that is decrypted at runtime.
          '';
        };

        mode = lib.mkOption {
          type = lib.types.str;
          default = "0400";
          example = "0440";
          apply = common.octalToInt;
          description = ''
            Permission mode of the decrypted file at runtime.
          '';
        };

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
    programs.fuse.userAllowOther = true;
    systemd = {
      automounts = lib.singleton {
        where = cfg.secretsDir;
        wantedBy = [ "multi-user.target" ];
      };
      mounts = lib.singleton {
        requires = [ "basic.target" ];
        after = [ "basic.target" ];
        what = toString cfg.metaFile;
        where = cfg.secretsDir;
        type = "fuse.agefs";
        options = lib.concatStringsSep "," options;
        mountConfig.Environment = "PATH=${
          lib.makeBinPath ([ cfg.package ] ++ cfg.pluginPackages)
        }:/run/wrappers/bin:/run/current-system/sw/bin";
      };
    };
  };
}
