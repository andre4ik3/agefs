{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.age;

  /**
    Converts an octal string like "0755" to a decimal integer like 493.
  */
  octalToInt =
    octalString:
    let
      split = builtins.split "([0-9])" octalString;
      digitLists = (builtins.filter builtins.isList split);
      digits = builtins.map (x: builtins.fromJSON (builtins.elemAt x 0)) digitLists;
      initial = {
        exp = 1;
        acc = 0;
      };
      op =
        digit:
        { exp, acc }:
        {
          exp = exp * 8;
          acc = acc + digit * exp;
        };
      folded = lib.foldr op initial digits;
    in
    folded.acc;

  args = [
    (lib.getExe cfg.package)
  ]
  ++ lib.map (path: "--identity=${path}") cfg.identityPaths
  ++ [
    cfg.metaFile
    cfg.secretsDir
  ];

  secretSubmodule = lib.types.submodule (
    { name, config, ... }:
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
          apply = octalToInt;
          description = ''
            Permission mode of the decrypted file at runtime.
          '';
        };
      };
    }
  );
in

{
  _class = "homeManager";

  options.age = {
    package = lib.mkPackageOption pkgs "agefs" { };

    metaFile = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = pkgs.writeText "agefs-meta.json" (
        builtins.toJSON (lib.mapAttrsToList (_: lib.id) cfg.secrets)
      );
      description = ''
        A file passed to agefs that contains metadata about the secrets to expose.
      '';
    };

    pluginPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        List of age plugins to add to agefs's PATH for decryption.
      '';
    };

    identityPaths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        List of identity paths to use. X25519, SSH, and plugin identities are
        supported. Encrypted identities as an Age file are NOT supported.
      '';
    };

    # TODO: change to agenix directory
    secretsDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.xdg.dataHome}/secrets";
      defaultText = lib.literalExpression ''
        "''${config.xdg.dataHome}/secrets"
      '';
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
    launchd.agents.agefs = {
      enable = lib.mkDefault true;
      config = {
        EnvironmentVariables.PATH = lib.makeBinPath cfg.pluginPackages;
        ProgramArguments = lib.map toString args;
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        StandardOutPath = "/tmp/agefs-home.log";
        StandardErrorPath = "/tmp/agefs-home.log";
      };
    };
  };
}
