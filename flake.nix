{
  inputs.nixpkgs.url = "https://nixpkgs.flake.andre4ik3.dev";

  outputs =
    { nixpkgs, self, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.agefs ];
        };
      eachSystem = f: lib.genAttrs systems (system: f (mkPkgs system));
    in
    {
      nixosModules = {
        default = {
          imports = [ self.nixosModules.agefs ];
          nixpkgs.overlays = [ self.overlays.default ];
        };
        agefs = ./modules/nixos.nix;
      };

      darwinModules = {
        default = {
          imports = [ self.darwinModules.agefs ];
          nixpkgs.overlays = [ self.overlays.default ];
        };
        agefs = ./modules/nix-darwin.nix;
      };

      homeModules = {
        default = {
          imports = [ self.homeModules.agefs ];
          nixpkgs.overlays = [ self.overlays.default ];
        };
        agefs = ./modules/home-manager.nix;
      };

      packages = eachSystem (pkgs: {
        default = pkgs.agefs;
        inherit (pkgs) agefs;
      });

      overlays = {
        default = self.overlays.agefs;
        agefs = final: prev: {
          agefs = final.callPackage ./package.nix { };
        };
      };

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            age
            go
            age-plugin-se
            age-plugin-tpm
          ];
        };
      });

      checks = eachSystem (
        pkgs:
        {
          # TODO: home-manager test
        }
        // lib.optionalAttrs pkgs.hostPlatform.isLinux {
          system = pkgs.testers.runNixOSTest {
            imports = [ ./tests/nixos.nix ];
            extraBaseModules.imports = [ self.nixosModules.agefs ];
          };
        }
      );
    };
}
