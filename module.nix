{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.services.easyroam =
    let
      types = lib.types;
    in
    {
      enable = lib.mkEnableOption "setup easyroam wifi configuration";
      pkcsFile = lib.mkOption {
        type = types.either types.path types.str;
        description = ''
          Path to the PKCS12 File (downloaded from the easyroam site).

          This will be extracted into the client certificate, root certificate and private key.
        '';
      };
      privateKeyPassPhrase = lib.mkOption {
        type = types.str;
        default = "memezlmao";
        description = ''
          Passphrase for the private key file. This doesnt actually need to be secure,
          since its useless without the specific private key file.
        '';
      };
      paths = {
        rootCert = lib.mkOption {
          type = types.str;
          description = "path to the root certificate pem file";
          default = "/run/easyroam/root-certificate.pem";
        };
        clientCert = lib.mkOption {
          type = types.str;
          description = "path to the client certificate pem file";
          default = "/run/easyroam/client-certificate.pem";
        };
        privateKey = lib.mkOption {
          type = types.str;
          description = "path to the private key pem file";
          default = "/run/easyroam/private-key.pem";
        };
      };
      mode = lib.mkOption {
        type = types.nullOr types.str;
        default = "0400";
        description = "mode (in octal notation) of the certificate files";
      };
      owner = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Owner of the certificate files";
      };
      group = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Group of the certificate files";
      };
      network = {
        configure = lib.mkEnableOption "also configure the easyroam network (otherwise only extraction will happen)";
        commonName = lib.mkOption {
          type = types.str;
          description = "Common Name (CN). This sadly cannot be read from a file.";
          example = "12345678910111213abcd@easyroam-pca.dfn.de";
        };
      };
    };

  config =
    let
      cfg = config.services.easyroam;
    in
    lib.mkIf cfg.enable {
      systemd.services.easyroam-install-certs = {
        wantedBy = [ "sysinit.target" ];
        after = [
          "systemd-sysusers.service"
          "sops-install-secrets.service"
        ];

        script = ''
          openssl=${pkgs.libressl}/bin/openssl

          mkdir -p "''${dirname ${cfg.paths.rootCert}}"
          mkdir -p "''${dirname ${cfg.paths.clientCert}}"
          mkdir -p "''${dirname ${cfg.paths.privateKey}}"

          # root cert
          $openssl pkcs12 -in "${cfg.pkcsFile}" -cacerts -passin pass: -nokeys > ${cfg.paths.rootCert}

          # client cert 
          $openssl pkcs12 -in "${cfg.pkcsFile}" -passin pass: -nokeys | $openssl x509 > ${cfg.paths.clientCert}

          # private key
          $openssl pkcs12 -in "${cfg.pkcsFile}" -nodes -nocerts -passin pass: | $openssl rsa -aes256 -passout pass:${cfg.privateKeyPassPhrase} > ${cfg.paths.privateKey}

          # set permissions
          chmod ${cfg.mode} "${cfg.paths.rootCert}" "${cfg.paths.clientCert}" "${cfg.paths.privateKey}"
          ${lib.optionalString (cfg.owner != null)
            ''chown ${cfg.owner} "${cfg.paths.rootCert}" "${cfg.paths.clientCert}" "${cfg.paths.privateKey}"''
          }
          ${lib.optionalString (cfg.group != null)
            ''chgrp ${cfg.group} "${cfg.paths.rootCert}" "${cfg.paths.clientCert}" "${cfg.paths.privateKey}"''
          }
        '';
      };

      networking.wireless.networks.eduroam = lib.mkIf cfg.network.configure {
        auth = ''
          key_mgmt=WPA-EAP
          proto=WPA2
          eap=TLS
          pairwise=CCMP
          group=CCMP
          altsubject_match="DNS:easyroam.eduroam.de"
          identity="${cfg.network.commonName}"
          ca_cert="${cfg.paths.rootCert}"
          client_cert="${cfg.paths.clientCert}"
          private_key="${cfg.paths.privateKey}"
          private_key_passwd="${cfg.privateKeyPassPhrase}"
        '';
      };
    };
}
