{
  description = "pared: Apple Intelligence controls and model cleanup for macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs =
    inputs:
    let
      systems = [ "aarch64-darwin" ];
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem = inputs.nixpkgs.lib.attrsets.genAttrs systems;
    in
    {
      packages = inputs.nixpkgs.lib.attrsets.genAttrs supportedSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          docs = import ./docs {
            inherit pkgs;
            revision = inputs.self.rev or "main";
          };
        in
        {
          docs = docs.html;
          docs-json = docs.json;
          profile = pkgs.writeText "disable-apple-intelligence.mobileconfig" (
            import ./nix/profile.nix { inherit (pkgs) lib; }
          );
          declarations = pkgs.writeText "pared-declarations.json" (
            builtins.toJSON (import ./nix/declarations.nix { inherit (pkgs) lib; })
          );
        }
        // inputs.nixpkgs.lib.attrsets.optionalAttrs (builtins.elem system systems) {
          pared = pkgs.callPackage ./nix/package.nix { };
          default = inputs.self.packages.${system}.pared;
        }
      );
      apps = eachSystem (system: {
        default = {
          type = "app";
          program = inputs.nixpkgs.lib.meta.getExe inputs.self.packages.${system}.pared;
        };
      });
      devShells = eachSystem (system: {
        default = inputs.nixpkgs.legacyPackages.${system}.mkShell {
          inputsFrom = [ inputs.self.packages.${system}.pared ];
        };
      });
      checks = inputs.nixpkgs.lib.attrsets.genAttrs supportedSystems (system: {
        cleanup = import ./nix/tests/cleanup.nix {
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        };
      });
      formatter = inputs.nixpkgs.lib.attrsets.genAttrs supportedSystems (
        system: inputs.nixpkgs.legacyPackages.${system}.nixfmt
      );
      darwinModules.default = ./nix/modules/darwin.nix;
      homeManagerModules.default = ./nix/modules/home-manager.nix;
    };
}
