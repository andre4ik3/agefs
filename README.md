agefs
=====

A FUSE filesystem that decrypts your secrets on-the-fly as they are accessed.

## Documentation

The flake provides an [agenix]-compatible module for NixOS, Nix-Darwin, and
Home-Manager.

If using plugins, add the plugin packages to `age.pluginPackages`. They will
automatically be added to the `$PATH` of `agefs`.

By default, each secret is decrypted every time it is accessed. This behavior
can be excessive when using plugins that require interactivity (such as Touch
ID using `age-plugin-se`). It's possible instead to keep the decrypted contents
loaded in memory after initial decryption, by enabling `age.keepCached = true`.

`agefs` does not (yet) support the client UI interface of `age` plugins. Any
plugins requiring interaction through this UI will fail.

On Darwin (both system and home), the module will wait by default for the
filesystem to become available before continuing with the activation. This
behavior can be disabled by setting `age.wait = false`.

The directory for Home-Manager secrets currently differs from `agenix`: it's
set to `~/.local/share/secrets` by default. You can override this using the
standard option `age.secretsDir`. The directory for system secrets is the same
by default, `/run/agenix`. It's recommended to query `age.secretsDir` and/or
`age.secrets.*.path` instead of hardcoding the secret directory location.

The rest of the options are (mostly) the same as [agenix], consult its
documentation (or view the module source in `modules/`) for more info.

This project only provides the runtime decryption module for Age secrets. For
secret editing and management, continue to use either the [agenix] or [ragenix]
CLI tools.

[agenix]: https://github.com/ryantm/agenix
[ragenix]: https://github.com/yaxitech/ragenix
