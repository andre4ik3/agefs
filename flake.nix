{
  inputs = {
    nixpkgs.url = "https://nixpkgs.flake.andre4ik3.dev";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    { nixpkgs, self, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      systems = import inputs.systems;
      eachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
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

      packages = eachSystem (pkgs: rec {
        default = agefs;
        agefs = pkgs.callPackage ./package.nix { };
      });

      overlays = rec {
        default = agefs;
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

      checks = eachSystem (pkgs: let
        pkgs' = import pkgs.path {
          inherit (pkgs) system;
          overlays = [ self.overlays.default ];
        };
      in {
        # TODO: home-manager test
      } // lib.optionalAttrs pkgs.hostPlatform.isLinux {
        system = pkgs'.testers.runNixOSTest {
          imports = [ ./tests/nixos.nix ];
          extraBaseModules.imports = [ self.nixosModules.agefs ];
        };
      });
    };
}
