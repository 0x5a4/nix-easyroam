# nix-easyroam

Setting up easyroam under NixOs is kind of a pain in the ass. The official app only
supports NetworkManager and x86 so if you configure your networks declaratively with nix or have
a non-x86 laptop you're kind of screwed. The pkcs file you can download also needs to be extracted
into multiple certificates.

This module aims to fix these issues by automatically extracting the pkcs file at startup using
a systemd service (similar to sops). You'll still need to redownload it every few months, but its much less tedious.
It can also automatically setup the `wpa_supplicant` or `NetworkManager` connection for you

The extracted Common Name/Root Certificate/Client Certificate/Private Key end up in `/run/easyroam/`, so you
can use them externally.

## Usage

### Step 1: Download the PKCS File

Go to [easyroam.de](https://easyroam.de), select your University and log in. Under `Manual Options` select `PKCS12` and generate the profile.

### Step 2 (optional): Encrypt the file using sops

If you dont encrypt the file, it will be copied to the nix-store and will
be world readable. You also cannot put it into a git repo or something

```bash
# copy the file into your secrets folder
cp file.p12 secrets/easyroam

# sops encrypt it in place
sops encrypt -i secrets/easyroam

# now setup the sops secret as usual
# i recommend settings the secrets restartUnits to [ "easyroam-install-certs.service" ]
```

### Step 3: Install the NixOS module

Do something like this in your flake

```nix
{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
    # its also possible to automatically configure wpa_supplicant
    network = {
        configure = true;
        # optional, backend to use for configuring the Network.
        # possible values: wpa_supplicant, NetworkManager
        # the default is wpa_supplicant
        backend = "";
        # optional, extra config appended to the wpa_supplicant network block
        wpa-supplicant.extraConfig = '';
            priority=5
        '';
        # optional, extra config appended to the network manager configuration
        networkmanager.extraConfig = {
            ipv6.addr-gen-mode = "default";
        };
    };
    # optional, if you want to override the passphrase for the private key file.
    # this doesnt need to be secret, since its useless without the private key file
    privateKeyPassPhrase = "";
    # optional, if you want to override where the extracted files end up
    # the defaults are:
    # /run/easyroam/common-name/
    # /run/easyroam/root-certificate.pem
    # /run/easyroam/client-certificate.pem
    # /run/easyroam/private-key.pem
    #
    # you can also read these from within your nix config using
    # `config.services.easyroam.paths`
    paths = {
       rootCert = "";
       clientCert = "";
       privateKey = "";
       commonName = "";
    };
    # optional, (permission bits) the files are stored as, (default is 0400 (0r--------))
    mode = "";
    # optional, owner and group of the files. (default is root)
    owner = "";
    group = "";
};
```

### Step 5: Repeat this every few months

Because easyroam is so much easier, you need to redo this every once in a while.

## Troubleshooting

### Certificate fails to be extracted

This is most likely because you copy-pasted the certificate for encryption and your editor appended a newline.
Prefer using `sops encrypt -i` for encrypting the file. This encrypts the file in place.
