# nix-easyroam

Setting up easyroam under NixOs is kind of a pain in the ass. The official app only
supports NetworkManager and x86 so if you configure your networks declaratively with nix or have
a non-x86 laptop you're kind of screwed. The pkcs file you can download also needs to be extracted
into multiple certificates.

This module aims to fix these issues by automatically extracting the pkcs file at startup using
a systemd service (similar to sops). You'll still need to redownload it every few months, but its much less tedious.
It can also automatically setup `wpa_supplicant` (via `networking.wireless`)

## Usage

### Step 1: Download the .p12 File

Go to [easyroam.de](https://easyroam.de), select your University and log in. Under `Manual Options` select `PKCS12` and generate the profile.

### Step 2: Obtain your Common Name

With the `.p12` file in Hand, run this command:

```bash
nix run github:0x5a4/nix-easyroam#extract-common-name file.p12
```

and write down the result. This is your identity/username.

### Step 3 (optional): Encrypt the file using sops

If you dont encrypt the file, it will be copied to the nix-store and will
be world readable. You also cannot put it into a git repo or something

```bash
# copy the file into your secrets folder
cp file.p12 secrets/easyroam

# sops encrypt it in place
sops encrypt -i secrets/easyroam

# now setup the sops secret as usual
```

### Step 4: Install the NixOS module

Do something like this in your flake

```nix
{
    inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    inputs.nix-easyroam.url = "github:0x5a4/nix-easyroam";

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

### Step 5: Configure the Module

Somewhere in your Nixos Config put:

```nix
services.easyroam = {
    enable = true;
    pkcsFile = "/path/to/the/file.p12"; # or e.g. config.sops.secrets.easyroam.path
    # optional, if you want to override the passphrase for the private key file.
    # this doesnt need to be secret, since its useless without the private key file
    privateKeyPassPhrase = "";
    # its also possible to automatically configure wpa_supplicant
    network = {
        configure = true;
        # the common name you got earlier. this cannot be read from a file, due to
        # limitations within wpa_supplicant. but putting this in your git repo should
        # be fine, since its only the username
        commonName = "";
    };
    # optional, if you want to override where the extracted files end up
    # the defaults are:
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
    };
    # optional, (permission bits) the files are stored as, (default is 0400 (0r--------))
    mode = "";
    # optional, owner and group of the files. (default is root)
    owner = "";
    group = "";
};
```

### Step 6: Repeat this every few months

Because easyroam is so much easier, you need to redo this every once in a while.
The Common Name stays the same, but the private key changes, so you need to redownload (and reencrypt)
the p12 file (dont forget to point nix to it).
