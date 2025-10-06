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
      nixosModules = rec {
        default = agefs;
        agefs = ./modules/nixos.nix;
      };

      darwinModules = rec {
        default = agefs;
        agefs = ./modules/nix-darwin.nix;
      };

      homeModules = rec {
        default = agefs;
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

      devShells = eachSystem (pkgs: rec {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            go
            age-plugin-se
            age-plugin-tpm
          ];
        };
      });
    };
}
