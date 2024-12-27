{
  description = "A NixOS Module for setting up easyroam";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  outputs =
    {
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      formatter = eachSystem (
        system: pkgs:
        (lib.flip treefmt-nix.lib.mkWrapper) {
          projectRootFile = "flake.nix";
          settings.on-unmatched = "debug";
          programs.nixfmt.enable = true;
        } pkgs
      );

      nixosModules.nix-easyroam = import ./module.nix;
    };
}
