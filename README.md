# nix-easyroam

This module allows you to declaratively set up easyroam using either `wpa_supplicant` or `NetworkManager`. It does so by using a systemd service that extracts the `pkcs` file on startup, similar to how `sops-nix` sets up its secrets. If you dont care about the declarative part, maybe have a look at the [official app](https://search.nixos.org/packages?channel=unstable&show=easyroam-connect-desktop). It only supports `NetworkManager` though.

The extracted Common Name/Root Certificate/Client Certificate/Private Key end up in `/run/easyroam/`, so you
can use them externally.

## Usage

### Step 1: Download the PKCS File

Go to [easyroam.de](https://easyroam.de), select your University and log in. Under `Manual Options` select `PKCS12` and generate the profile.

### Step 2 (optional): Encrypt the file using sops

If you dont encrypt the file, it will be copied to the nix-store and will
be world readable. You also cannot safely put it into a git repo or something

```bash
# copy the file into your secrets folder
cp file.p12 secrets/easyroam

# sops encrypt it in place
sops encrypt -i secrets/easyroam

# now setup the sops secret as usual
# i recommend setting the secrets restartUnits to [ "easyroam-install.service" ]
```

### Step 3: Install the NixOS module

Do something like this in your flake (add this repo as an input and import the module)

```nix
{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
        nix-easyroam.url = "github:0x5a4/nix-easyroam";
    };

    outputs = {nixpkgs, nix-easyroam, ...}: {
        nixosConfigurations.mysystem = nixpkgs.lib.nixosSystem {
            modules = [
                # ...
                nix-easyroam.nixosModules.nix-easyroam
                # ...
            ];
        };
    };
}
```

### Step 4: Configure the Module

Somewhere in your Nixos Config put:

```nix
services.easyroam = {
    enable = true;
    pkcsFile = "/path/to/the/file.p12"; # or e.g. config.sops.secrets.easyroam.path
    # automatically configure wpa-supplicant (use this if you configure your networking via networking.wireless)
    wpa-supplicant = {
        enable = true;
        # optional, extra config to write into the wpa_supplicant network block
        # extraConfig = '';
        #    priority=5
        # '';
    };
    # automatically configure NetworkManager
    networkmanager = {
        enable = true;
        # optional, extra config to write into the NetworkManager config
        # extraConfig = {
        #    ipv6.addr-gen-mode = "default";
        # };
    };
    # optional, if you want to override the passphrase for the private key file.
    # this doesnt need to be secret, since its useless without the private key file
    # privateKeyPassPhrase = "";
    # optional, if you want to override where the extracted files end up
    # the defaults are:
    # /run/easyroam/common-name/
    # /run/easyroam/root-certificate.pem
    # /run/easyroam/client-certificate.pem
    # /run/easyroam/private-key.pem
    #
    # you can also read these from within your nix config using
    # `config.services.easyroam.paths`
    # paths = {
    #   rootCert = "";
    #   clientCert = "";
    #   privateKey = "";
    #   commonName = "";
    # };
    # optional, (permission bits) the files are stored as, (default is 0400 (0r--------))
    # mode = "";
    # optional, owner and group of the files. (default is root)
    # owner = "";
    # group = "";
};
```

### Step 5: Repeat this every few months

Because easyroam is so much easier, you need to redo this every once in a while.

## Troubleshooting

### Connection cant be established

Do you still have your old eduroam connection set up? Remove it and run `sudo systemctl restart easyroam-install.service`.

### Certificate fails to be extracted

This is most likely because you copy-pasted the certificate for encryption and your editor appended a newline.
Prefer using `sops encrypt -i` for encrypting the file. This encrypts the file in place.
