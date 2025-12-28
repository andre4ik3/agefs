{
  buildGoModule,
  makeWrapper,
  stdenv,
  fuse3,
  fuse,
  lib,
}:

let
  platformFuse = if stdenv.hostPlatform.isLinux then fuse3 else fuse;
in

buildGoModule (finalAttrs: {
  pname = "agefs";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-pZw6JUiy9XOKGf9VLd58fHSw58tbh/Dkbv5ywtdN944=";

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    ln -s agefs "$out/bin/mount.agefs"
    ln -s agefs "$out/bin/mount.fuse.agefs"
    ln -s bin "$out/sbin"
  '';

  postFixup = ''
    wrapProgram "$out/bin/agefs" --prefix PATH : "${
      lib.makeBinPath [
        "/run/wrappers"
        platformFuse
      ]
    }"
  '';

  meta = {
    mainProgram = "agefs";
    description = "A FUSE filesystem that decrypts age secrets on-the-fly as they are accessed.";
    license = lib.licenses.mit;
  };
})
