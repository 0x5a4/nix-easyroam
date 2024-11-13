{
  description = "A NixOS Module for easyroam";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      lib = nixpkgs.lib;

      forAllSystems = lib.genAttrs systems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      nixosModules.nix-easyroam = import ./module.nix;

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          extract-common-name = pkgs.writeShellApplication {
            name = "extract-common-name";

            runtimeInputs = with pkgs; [
              libressl
              gnused
            ];

            text = ''
                if (( $# == 0 )); then
                    echo "usage: extrac-common-name <pkcs-file>"
                    exit
                fi

              openssl pkcs12 -in "$1" -passin pass: -nokeys | \
                openssl x509 -noout -subject | sed -rn 's/.*\/CN=(.*)\/C.*/\1/gp'
            '';
          };
        }
      );

      apps = forAllSystems (system: {
        extract-common-name = {
          type = "app";
          program = "${self.packages.${system}.extract-common-name}/bin/extract-common-name";
        };
      });
    };
}
