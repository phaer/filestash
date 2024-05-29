{ config, lib, pkgs, ... }:
let
    cfg = config.services.filestash;
    settingsFormat = pkgs.formats.json {};
    defaults = {
        general = {
            name = null;
            port = null;
            host = null;
            force_ssl = null;
            editor = null;
            fork_button = null;
            logout = null;
            display_hidden = null;
            refresh_after_upload = null;
            upload_button = null;
            upload_pool_size = null;
            filepage_default_view = null;
            filepage_default_sort = null;
            cookie_timeout = null;
            custom_css = null;
        };

        features = {
            api = {
                enable = null;
            };
            share = {
                enable = null;
                default_access = null;
                redirect = null;
            };
            protection = {
                iframe = null;
                enable_chromecast = null;
                disable_svg = null;
                zip_timeout = null;
                disable_csp = null;
            };
            search = {
                explore_timeout = null;
            };
            video = {
                blacklist_format = null;
                enable_transcoder = null;
            };
            office = {
                enable = null;
                onlyoffice_server = null;
                onlyoffice_jwt_secret = null;
                can_download = null;
            };
        };

        log = {
            enable = null;
            level = null;
            telemetry = null;
        };
        email = {
            server = null;
            port = null;
            username = null;
            from = null;
        };
        auth = {};
        middleware = {};
        connections = [];
    }
    ;
in {
    options.services.filestash = with lib.types; {
        enable = lib.mkEnableOption "filestash";
        package = lib.mkOption {
            type = package;
            default = pkgs.filestash;
            defaultText = "pkgs.filestash";
            description = ''
        Which filestash package to use.
      '';
        };
        dataDir = lib.mkOption {
            default = "/var/lib/filestash";
            type = str;
        };
        secretKeyPath = lib.mkOption {
            description = "Path to a file containing general.secret_key";
            default = "/var/run/secrets/filestash/secret_key";
            type = path;
        };
        adminPasswordPath = lib.mkOption {
            description = "Path to a file containing auth.admin";
            default = "/var/run/secrets/filestash/admin_password";
            type = path;
        };
        apiKeyPath = lib.mkOption {
            description = "Path to a file containing features.api.api_key";
            default = null;
            example = "/var/run/secrets/filestash/api_key";
            type = nullOr path;
        };
        emailPasswordPath = lib.mkOption {
            description = "Path to a file containing email.password";
            default = null;
            example = "/var/run/secrets/filestash/email_password";
            type = nullOr path;
        };

        settings = lib.mkOption {
            type = submodule {
                freeformType = settingsFormat.type;

                options = {
                    general.name = lib.mkOption {
                        type = nullOr str;
                        default = "My Filestash Cloud";
                        description = "Human-readable name of this instance";
                    };

                    general.host = lib.mkOption {
                        type = nullOr str;
                        default = "localhost";
                        description = "Host to listen on";
                    };

                    general.port = lib.mkOption {
                        type = nullOr port;
                        default = 8080;
                        description = "Port to listen on";
                    };
                };
            };
        };
    };
    config = lib.mkIf cfg.enable {
        users.users.filestash = {
            isSystemUser = true;
            group = "filestash";
        };
        users.groups.filestash = {};

        systemd = {
            tmpfiles.rules = [
                "d  ${cfg.dataDir}/data        0771 filestash filestash - -"
                "d  ${cfg.dataDir}/data/state  0771 filestash filestash - -"
                "d  ${cfg.dataDir}/state/config  0771 filestash filestash - -"
                "f  ${cfg.dataDir}/state/config/config.json  0771 filestash filestash - -"
            ];
            services.filestash = {
                preStart = let
                    configPath = "${cfg.dataDir}/state/config/config.json";
                    diffPath = "${cfg.dataDir}/state/config/.config.json.diff";
                    newConfig = settingsFormat.generate "filestash.json" (lib.recursiveUpdate defaults cfg.settings);
                in ''
                  if [ -f "${configPath}" ]
                  then
                    configDiff="$(${pkgs.diffutils}/bin/diff "${configPath}" "${newConfig}" || true)"
                    if [ ! -z "$configDiff" ]
                    then
                        echo "Saving old config to ${diffPath}"
                        echo "''$configDiff" > "${diffPath}"
                    else
                        echo "Config is the same as last run"
                    fi
                  fi
                  echo "Updating config"
                  ${pkgs.jq}/bin/jq \
                    --rawfile secretKey ${cfg.secretKeyPath} \
                    --rawfile adminPassword ${cfg.adminPasswordPath} \
                    ${lib.optionalString (cfg.apiKeyPath != null) "--rawfile apiKey ${cfg.apiKeyPath}"} \
                    ${lib.optionalString (cfg.emailPasswordPath != null) "--rawfile emailPassword ${cfg.emailPasswordPath}"} \
                    '
                        .general.secret_key = $secretKey
                        | .auth.admin = $adminPassword
                        ${lib.optionalString (cfg.apiKeyPath != null) "| .features.api.api_key = $apiKey"}
                        ${lib.optionalString (cfg.emailPasswordPath != null) "| .email.password = $emailPassword"}
                    ' \
                    ${newConfig} \
                    > "${configPath}"
                    export CONFIG_SECRET="$(cat "${cfg.secretKeyPath}")"
                '';
                description = "A modern web client for SFTP and more";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target"  ];
                after = [ "network-online.target" ];
                serviceConfig = {
                    User = "filestash";
                    Group = "filestash";

                    Type = "simple";
                    ExecStart = "${pkgs.bash}/bin/bash -c 'FILESTASH_PATH=$STATE_DIRECTORY ${lib.getExe cfg.package}'";
                    Restart = "always";
                    StateDirectory = baseNameOf cfg.dataDir;
                    StateDirectoryMode = "0750";
                };
            };
        };
    };
}
