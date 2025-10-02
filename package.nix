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
  vendorHash = "sha256-CHLKtT16TfFecwKjz1Gpo7XvsiQyvn6JMi/AgTo/oeE=";
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    ln -s agefs "$out/bin/mount.agefs"
    ln -s agefs "$out/bin/mount.fuse.agefs"
    ln -s bin "$out/sbin"
  '';
  postFixup = ''
    wrapProgram "$out/bin/agefs" --prefix PATH : "/run/wrappers/bin:${lib.makeBinPath [ platformFuse ]}"
  '';
  meta = {
    mainProgram = "agefs";
    license = lib.licenses.mit;
  };
})
