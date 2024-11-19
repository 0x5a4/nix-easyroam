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
      type = types.either types.path types.nonEmptyStr;
      description = ''
        Path to the PKCS12 File (downloaded from the easyroam site).

        This will be extracted into the client certificate, root certificate and private key.
      '';
    };
    privateKeyPassPhrase = lib.mkOption {
      type = types.nonEmptyStr;
      default = "memezlmao";
      description = ''
        Passphrase for the private key file. This doesnt actually need to be secure,
        since its useless without the specific private key file.
      '';
    };
    paths = {
      commonName = lib.mkOption {
        type = types.nonEmptyStr;
        description = "path to the common name file";
        default = "/run/easyroam/common-name";
      };
      rootCert = lib.mkOption {
        type = types.nonEmptyStr;
        description = "path to the root certificate pem file";
        default = "/run/easyroam/root-certificate.pem";
      };
      clientCert = lib.mkOption {
        type = types.nonEmptyStr;
        description = "path to the client certificate pem file";
        default = "/run/easyroam/client-certificate.pem";
      };
      privateKey = lib.mkOption {
        type = types.nonEmptyStr;
        description = "path to the private key pem file";
        default = "/run/easyroam/private-key.pem";
      };
    };
    mode = lib.mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = "0400";
      description = "mode (in octal notation) of the certificate files";
    };
    owner = lib.mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Owner of the certificate files";
    };
    group = lib.mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Group of the certificate files";
    };
    wpa-supplicant = {
      enable = lib.mkEnableOption "automatically configure wpa_supplicant";
      extraConfig = lib.mkOption {
        type = types.lines;
        default = "";
        description = "Extra config to write into the network Block";
        example = ''
          priority=5
        '';
      };
    };
    networkmanager = {
      enable = lib.mkEnableOption "automatically configure wpa_supplicant";
      extraConfig = lib.mkOption {
        type = ini.type;
        default = { };
        description = ''
          Extra config to write into the network manager config.
          This attrset will be merged with the default, so you can override it here
        '';
      };
    };
  };

  imports = [
    (lib.mkRemovedOptionModule [
      "services"
      "easyroam"
      "network"
      "configure"
    ] "Use services.easyroam.wpa-supplicant.enable or services.easyroam.networkmanager.enable instead")

    (lib.mkRenamedOptionModule
      [
        "services"
        "easyroam"
        "network"
        "extraConfig"
      ]
      [
        "services"
        "easyroam"
        "wpa-supplicant"
        "extraConfig"
      ]
    )
  ];

  config =
    let
      cfg = config.services.easyroam;
      wpaCfg = config.networking.wireless;

      wpaUnitServices =
        if wpaCfg.interfaces == [ ] then
          [ "wpa_supplicant.service" ]
        else
          builtins.map (x: "wpa_supplicant-${x}.service") wpaCfg.interfaces;

      networkManagerConfig = lib.recursiveUpdate cfg.networkmanager.extraConfig {
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
    in
    lib.mkIf cfg.enable {
      systemd.services.easyroam-install = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "sops-install-secrets.service" ];

        after = [ "NetworkManager.service" ] ++ wpaUnitServices;
        before = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          UMask = "0177";
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
                   ${cfg.wpa-supplicant.extraConfig}
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

            ${lib.optionalString cfg.wpa-supplicant.enable ''
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

              echo reloading wpa_supplicant config file
              ${
                if wpaCfg.interfaces == [ ] then
                  ''
                    for NAME in $(find -H /sys/class/net/* -name wireless | cut -d/ -f 5); do
                      IFACES+="$NAME"
                    done
                  ''
                else
                  lib.concatMapStringsSep "\n" (s: "IFACES+=\"${s}\"") wpaCfg.interfaces
              }

              for IFACE in $IFACES; do 
                echo reloading interface $IFACE
                ${pkgs.wpa_supplicant}/bin/wpa_cli "-i$IFACE" reconfigure
              done
            ''}

            ${lib.optionalString cfg.networkmanager.enable ''
              # set up NetworkManager
              NMPATH=/run/NetworkManager/system-connections
              mkdir -p "$NMPATH"

              sed -e "s/EASYROAM_IDENTITY_PLACEHOLDER/''$(cat ${cfg.paths.commonName})/g" "${nmNetworkBlock}" > "''${NMPATH}/eduroam.nmconnection"

              echo reloading network manager connections
              ${pkgs.networkmanager}/bin/nmcli connection reload

              echo success
            ''}
          '';
      };

      networking.wireless = lib.mkIf cfg.wpa-supplicant.enable {
        allowAuxiliaryImperativeNetworks = true;
        userControlled.enable = true;
      };
    };
}
