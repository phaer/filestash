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
                api_key = null;
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
            password = null;
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
                "d  ${cfg.dataDir}/data        0771 - - - -"
                "d  ${cfg.dataDir}/data/state  0771 - - - -"
                "d  ${cfg.dataDir}/config  0771 - - - -"
                "f  ${cfg.dataDir}/config/config.json  0771 - - - -"
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
                  install -m 660 -T "${newConfig}" "${configPath}"
                '';
                description = "A modern web client for SFTP and more";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" ];
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
