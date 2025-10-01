{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = { nixpkgs, self, ... }@inputs: let
    inherit (nixpkgs) lib;
    systems = import inputs.systems;
    eachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    makePackage = pkgs: pkgs.buildGoModule (finalAttrs: {
      pname = "agefs";
      version = "0.1.0";
      src = ./.;
      vendorHash = "sha256-EcrR5UfqZZg0r8RZIu0acDk+DYuQXc1NILH5DACY2Pk=";
      meta = {
        mainProgram = "agefs";
        license = lib.licenses.mit;
      };
    });
  in {
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
      agefs = makePackage pkgs;
    });

    overlays = rec {
      default = agefs;
      agefs = final: prev: {
        agefs = makePackage final;
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