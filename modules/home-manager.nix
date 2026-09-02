{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.age;
  common = import ./common.nix { inherit pkgs lib; };

  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;

  options =
    lib.map (path: "identity=${path}") cfg.identityPaths
    ++ lib.optional isLinux "x-gvfs-hide"
    ++ lib.optional isDarwin "nobrowse"
    ++ lib.optional cfg.keepCached "keep_cached";

  args = [
    (lib.getExe cfg.package)
    "-o"
    (lib.concatStringsSep "," options)
  ]
  ++ lib.optional isDarwin "-f"
  ++ [
    cfg.metaFile
    cfg.secretsDir
  ];

  secretSubmodule = lib.types.submodule (
    { config, name, ... }:
    {
      options = common.secretOpts { inherit common name; };
      config.path = "${cfg.secretsDir}/${config.name}";
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
        ProgramArguments = map toString args;
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
      };
    };

    systemd.user.services.agefs = {
      Unit.Description = "Age Encrypted File System";
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "forking";
        ExecStart = lib.escapeShellArgs args;
        Environment = "PATH=${
          lib.makeBinPath ([ cfg.package ] ++ cfg.pluginPackages)
        }:/run/wrappers/bin:/run/current-system/sw/bin";
        Restart = "on-failure";
      };
    };

    home.activation = lib.mkIf (isDarwin && cfg.wait) {
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
