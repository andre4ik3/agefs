{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.age;
  common = import ./common.nix { inherit pkgs lib; };
  utils = import "${pkgs.path}/nixos/lib/utils.nix" {
    inherit lib pkgs;
    config = { };
  };

  options =
    lib.map (path: "identity=${path}") cfg.identityPaths
    ++ lib.optional pkgs.hostPlatform.isLinux "x-gvfs-hide"
    ++ lib.optional pkgs.hostPlatform.isDarwin "nobrowse"
    ++ lib.optional cfg.keepCached "keep_cached";

  args = [
    (lib.getExe cfg.package)
    "-o"
    (lib.concatStringsSep "," options)
  ]
  ++ lib.optional pkgs.hostPlatform.isDarwin "-f"
  ++ [
    cfg.metaFile
    cfg.secretsDir
  ];

  secretSubmodule = lib.types.submodule (
    { name, ... }:
    {
      options = common.secretOpts { inherit common name; };
    }
  );
in

{
  _class = "homeManager";

  options.age = common.rootOptions cfg // {
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
      };
    };

    systemd.user = {
      # Regular users don't have permissions to do automounts
      # automounts.${utils.escapeSystemdPath cfg.secretsDir} = {
      #   Automount.Where = cfg.secretsDir;
      #   Install.WantedBy = [ "default.target" ];
      # };
      mounts.${utils.escapeSystemdPath cfg.secretsDir} = {
        Unit.Description = "Age Encrypted File System";
        Mount = {
          What = cfg.metaFile;
          Where = cfg.secretsDir;
          Type = "fuse.agefs";
          Options = lib.concatStringsSep "," options;
          Environment = "PATH=${
            lib.makeBinPath ([ cfg.package ] ++ cfg.pluginPackages)
          }:/run/wrappers/bin:/run/current-system/sw/bin";
        };
        Install.WantedBy = [ "basic.target" ];
      };
    };

    home.activation = lib.mkIf (pkgs.hostPlatform.isDarwin && cfg.wait) {
      agefs = lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        if [[ ! -e "${cfg.secretsDir}/.agefs" ]]; then
          /sbin/umount "${cfg.secretsDir}" > /dev/null || true
          /bin/launchctl kickstart -k gui/$(id -u)/org.nix-community.home.agefs
          echo "waiting for agefs..."
          /bin/wait4path "${cfg.secretsDir}"/.agefs
        fi
      '';
    };
  };
}
