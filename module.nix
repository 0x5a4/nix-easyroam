{
  config,
  lib,
  pkgs,
  ...
}:
let
  types = lib.types;
  ini = pkgs.formats.ini { };
in
{
  options.services.easyroam = {
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
      commonName = lib.mkOption {
        type = types.str;
        description = "path to the common name file";
        default = "/run/easyroam/common-name";
      };
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
      wpa-supplicant.extraConfig = lib.mkOption {
        type = types.lines;
        default = "";
        description = "Extra config to write into the network Block";
        example = ''
          priority=5
        '';
      };
      networkmanager.extraConfig = lib.mkOption {
        type = ini.type;
        default = { };
        description = ''
          Extra config to write into the network manager config.
          This attrset will be merged with the default, so you can override the default here
        '';
      };
      backend = lib.mkOption {
        type = types.enum [
          "wpa_supplicant"
          "NetworkManager"
        ];
        default = "wpa_supplicant";
        description = "Backend to use for configuring the network";
      };
    };
  };

  config =
    let
      cfg = config.services.easyroam;
      wpaCfg = config.networking.wireless;

      wantsWpa = cfg.network.configure && cfg.network.backend == "wpa_supplicant";
      wantsNm = cfg.network.configure && cfg.network.backend == "NetworkManager";

      wpaUnitNames =
        if wpaCfg.interfaces == [ ] then
          [ "wpa_supplicant" ]
        else
          builtins.map (x: "wpa_supplicant-${x}") wpaCfg.interfaces;

      wpaUnitServices = builtins.map (x: "${x}.service") wpaUnitNames;

      networkManagerConfig = lib.recursiveUpdate cfg.network.networkmanager.extraConfig {
        connection = {
          id = "eduroam";
          type = "wifi";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "eduroam";
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-eap";
        };
        "802-1x" = {
          altsubject-matches = "DNS:easyroam.eduroam.de;";
          ca-cert = "${cfg.paths.rootCert}";
          client-cert = "${cfg.paths.clientCert}";
          eap = "tls;";
          identity = "EASYROAM_IDENTITY_PLACEHOLDER";
          private-key = cfg.paths.privateKey;
          private-key-password = cfg.privateKeyPassPhrase;
        };
        ipv4.method = "auto";
        ipv6 = {
          addr-gen-mode = "stable-privacy";
          method = "auto";
        };
      };

      easyroam-unit = {
        wantedBy = [ "multi-user.target" ];

        wants = [
          "sops-install-secrets.service"
        ] ++ (lib.optionals wantsWpa wpaUnitServices);

        after = lib.optional wantsNm "NetworkManager.service";

        before = (lib.optionals wantsWpa wpaUnitServices) ++ (lib.optional wantsNm "network-online.target");

        serviceConfig = {
          UMask = "0177";
          RemainAfterExit = "yes";
        };

        script =
          let
            wpaNetworkBlock = pkgs.writeTextFile {
              name = "easyroam-wpa-network-block";
              text = ''
                #begin easyroam config
                network={
                   ssid="eduroam"
                   scan_ssid=1
                   key_mgmt=WPA-EAP
                   proto=WPA2
                   eap=TLS
                   pairwise=CCMP
                   group=CCMP
                   altsubject_match="DNS:easyroam.eduroam.de"
                   identity="EASYROAM_IDENTITY_PLACEHOLDER"
                   ca_cert="${cfg.paths.rootCert}"
                   client_cert="${cfg.paths.clientCert}"
                   private_key="${cfg.paths.privateKey}"
                   private_key_passwd="${cfg.privateKeyPassPhrase}"
                   ${cfg.network.wpa-supplicant.extraConfig}
                }
                #end easyroam config
              '';
            };
            nmNetworkBlock = ini.generate "easyroam-nm-network-block" networkManagerConfig;
          in
          ''
            openssl=${pkgs.libressl}/bin/openssl

            ${lib.concatMapStringsSep "\n" (str: ''mkdir -p "''$(dirname ${str})"'') (
              with cfg.paths;
              [
                commonName
                rootCert
                clientCert
                privateKey
              ]
            )}

            # common name
            $openssl pkcs12 -in "${cfg.pkcsFile}" -passin pass: -nokeys | $openssl x509 -noout -subject | sed -rn 's/.*\/CN=(.*)\/C.*/\1/gp' > ${cfg.paths.commonName}
              
            # root cert
            $openssl pkcs12 -in "${cfg.pkcsFile}" -passin pass: -nokeys -cacerts > ${cfg.paths.rootCert}

            # client cert 
            $openssl pkcs12 -in "${cfg.pkcsFile}" -passin pass: -nokeys | $openssl x509 > ${cfg.paths.clientCert}

            # private key
            $openssl pkcs12 -in "${cfg.pkcsFile}" -passin pass: -nocerts -nodes | $openssl rsa -aes256 -passout pass:${cfg.privateKeyPassPhrase} > ${cfg.paths.privateKey}

            # set permissions
            ${lib.concatMapStringsSep "\n"
              (str: ''
                chmod "${cfg.mode}" "${str}"
                ${lib.optionalString (cfg.owner != null) ''chown "${cfg.owner}" "${str}"''}
                ${lib.optionalString (cfg.group != null) ''chgrp "${cfg.group}" "${str}"''}
              '')
              (
                with cfg.paths;
                [
                  commonName
                  rootCert
                  clientCert
                  privateKey
                ]
              )
            }

            echo pkcs file sucessfully extracted

            ${lib.optionalString wantsWpa ''
              # set up wpa_supplicant
              if grep -q "#begin easyroam config" /etc/wpa_supplicant.conf; then
                # dont know why this is necessary, but if we just make it one big pipe, one of the sed's
                # gets a SIGPIPE and just dies.
                NETWORK_BLOCK=$(sed -e "s/EASYROAM_IDENTITY_PLACEHOLDER/''$(cat ${cfg.paths.commonName})/g" "${wpaNetworkBlock}" | \
                  sed -re '/#begin easyroam config/,/#end easyroam config/{r /dev/stdin' -e 'd;}' /etc/wpa_supplicant.conf)
                echo "$NETWORK_BLOCK" > /etc/wpa_supplicant.conf
              else
                cat ${wpaNetworkBlock} | sed "s/EASYROAM_IDENTITY_PLACEHOLDER/''$(cat ${cfg.paths.commonName})/g" >> /etc/wpa_supplicant.conf
              fi
            ''}

            ${lib.optionalString wantsNm ''
              # set up NetworkManager
              NMPATH=/run/NetworkManager/system-connections
              mkdir -p "$NMPATH"

              sed -e "s/EASYROAM_IDENTITY_PLACEHOLDER/''$(cat ${cfg.paths.commonName})/g" "${nmNetworkBlock}" > "''${NMPATH}/eduroam.nmconnection"

              ${pkgs.networkmanager}/bin/nmcli connection reload
            ''}
          '';
      };
    in
    lib.mkIf cfg.enable {
      systemd.services = lib.mergeAttrsList [
        (lib.optionalAttrs wantsWpa (
          lib.genAttrs wpaUnitNames (x: {
            bindsTo = [ "easyroam-install-certs.service" ];
          })
        ))
        {
          easyroam-install-certs = easyroam-unit;
        }
      ];

      networking.wireless.allowAuxiliaryImperativeNetworks = lib.mkIf wantsWpa true;
    };
}
