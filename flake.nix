{
  description = "A NixOS Module for easyroam";

  outputs =
    { ... }:
    {
      nixosModules.easyroam = import ./module.nix;
    };
}
