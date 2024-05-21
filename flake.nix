{
  inputs.systems.url = "github:nix-systems/default";
  outputs = { self, nixpkgs, systems }:
    let
      lib = builtins // nixpkgs.lib;
      eachSystem = lib.genAttrs (import systems);
      fs = lib.fileset;

      makeFrontend = pkgs:
          pkgs.buildNpmPackage (lib.fix (finalAttrs: let
              packageJson = lib.importJSON ./package.json;
          in {
              pname = packageJson.name;
              version = packageJson.version;
              src = fs.toSource {
                  root = ./.;
                  fileset = fs.difference
                      (fs.fromSource (lib.sources.cleanSource ./.))
                      (fs.unions (map fs.maybeMissing [
                          ./flake.nix
                          ./flake.lock
                          ./node_modules
                      ]));
              };


              npmFlags = [ "--legacy-peer-deps" ];
              npmInstallFlags = [ "--include=dev" ];
              npmDepsHash = "sha256-G9UcUKc83Hx26frGcpSPsSykw23AdYMCgVlSMp+AW/U=";
              makeCacheWritable = true;

              patches = [
                  ./patches/disable-plg-image-c.patch
                  ./patches/vm-in-asn1.patch
              ];

              buildPhase = ''
                go generate -x ./server/...
                make build_frontend
                pushd public
                make compress
                popd
              '';

              postFixup = ''
                find . -path ./node_modules -prune -o -exec cp -r '{}' "$out/lib/node_modules/filestash/{}" ';'
              '';

              nativeBuildInputs = [
                  pkgs.go
                  pkgs.pkg-config
                  pkgs.brotli
                  pkgs.gzip
                  pkgs.git
                  pkgs.gnumake
              ];
          }));

      makeBackend = pkgs: frontend:
          pkgs.buildGoModule (lib.fix (finalAttrs: {
              inherit (frontend) pname version;
              src = "${frontend}/lib/node_modules/filestash";

              vendorHash = "sha256-B2QHF6hE+Z/6X76kqYb5WO6prt8epwjy14c/tOKUZpc=";

              buildPhase = ''
                mkdir -p $out/bin
                go build --tags "fts5" -o $out/bin/filestash cmd/main.go
                cp config/config.json $out/config.dist.json
              '';

              postInstall = ''
                   wrapProgram $out/bin/filestash \
                     --prefix PATH : ${lib.makeBinPath finalAttrs.propagatedBuildInputs}
              '';

              propagatedBuildInputs = [
                  pkgs.curl
                  pkgs.emacs-nox
                  pkgs.ffmpeg
                  pkgs.zip
                  pkgs.poppler_utils.out
              ];
              nativeBuildInputs = [
                  pkgs.makeWrapper
                  pkgs.pkg-config
                  pkgs.gnumake
                  pkgs.curl
              ];
              buildInputs = [
                  pkgs.vips.dev
                  pkgs.libjpeg.dev
                  pkgs.libtiff.dev
                  pkgs.libpng.dev
                  pkgs.libwebp
                  pkgs.libraw.dev
                  pkgs.libheif.dev
                  pkgs.giflib
              ];
          }));
    in
      {
        packages = eachSystem (system: {
          nodejs = nixpkgs.legacyPackages.${system}.nodejs;
          npm = self.packages.${system}.nodejs.pkgs.npm;
          frontend = makeFrontend nixpkgs.legacyPackages.${system};
          backend = makeBackend nixpkgs.legacyPackages.${system} self.packages.${system}.frontend;
          filestash = self.packages.${system}.backend;
        });
        devShells = eachSystem (system: {
          default =  with self.packages.${system}; nixpkgs.legacyPackages.${system}.mkShell {
            packages = [
              nodejs
              npm
            ];
            shellHook = ''
              PATH=$PWD/node_modules/.bin:$PATH
            '';
            # ln -sfT ${website}/lib/node_modules/${website.pname}/node_modules $PWD/node_modules
          };
        });
      };
}
