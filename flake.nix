{
  description = "A NixOS Module for setting up easyroam";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
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
        pkgs.writers.writeBashBin "fmt" ''
          find . -type f -name \*.nix | xargs ${lib.getExe pkgs.nixfmt-rfc-style}
        ''
      );

      nixosModules.nix-easyroam = import ./module.nix;
    };
}
