{ pkgs, lib }:

{
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

  /**
    Common options for the age top-level option.
  */
  rootOptions = cfg: {
    package = lib.mkPackageOption pkgs "agefs" { };

    keepCached = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Whether to keep decrypted secret contents in-memory after decryption.
        If false (the default), the file contents are decrypted every time the
        file is opened. If true, the file contents are decrypted the first time
        the file is opened, and then stored in memory.
      '';
    };

    wait = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether to wait for agefs to mount as part of system activation.
        Currently only supported on Darwin (both system and home).
      '';
    };

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
  };

  /**
    Common options for secrets in the age.secrets option.
  */
  secretOpts =
    { common, name }:
    {
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
    };

  tryMaybeGetId =
    thing: entity: attrs: val:
    let
      intVal = builtins.tryEval (lib.toInt val);
    in
    if builtins.isString val then
      attrs.${val}.id or (
        if intVal.success then
          intVal.value
        else
          throw ''
            agefs requires a ${thing} to be set, but ${entity} ${val} does not have one.
          ''
      )
    else
      val;
}
