{
  description = "A NixOS Module for easyroam";

  outputs =
    { ... }:
    {
      nixosModules.nix-easyroam = import ./module.nix;
    };
}
