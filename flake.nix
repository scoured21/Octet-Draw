{
  description = "Octet Draw — chemical structure drawing editor (built from source, no AppImage)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        version = "1.0.27";
        src = pkgs.fetchFromGitHub {
          owner = "SamChemMan";
          repo = "Octet-Draw";
          rev = "v${version}";
          hash = "sha256-qRIDRzQpRKgsJnU1yUImkBIOtNT/KbtaCjvohZsk0DI=";
        };

        # Node 24, as required by the project README
        nodejs = pkgs.nodejs_24;

        # Stage 1: build the Vite/React frontend (produces dist/)
        frontend = pkgs.buildNpmPackage rec {
          pname = "octet-draw-frontend";
          inherit version src nodejs;

          # buildNpmPackackage builds the root of the repo
          sourceRoot = "${src.name}";

          npmDepsHash = "sha256-yKmbG/9M5xISTldy69m1cBUVr2EoqNzE9LRkjOGRpwY=";

          dontNpmBuild = false;
          npmBuildScript = "build"; # tsc && vite build

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r dist $out/dist
            runHook postInstall
          '';

          # vite needs writable cache dirs even if HOME is set
          env.CI = "true";
        };

        # Stage 2: build the Tauri 2 (Rust) app, embedding the frontend dist
        octet-draw = pkgs.rustPlatform.buildRustPackage rec {
          pname = "octet-draw";
          inherit version src;

          # cargo runs inside src-tauri/
          sourceRoot = "${src.name}/src-tauri";

          # Tauri expects the frontend at ../dist relative to src-tauri,
          # and embeds it into the binary at compile time.
					postPatch = ''
						chmod u+w ..
						mkdir -p ../dist
						cp -r ${frontend}/dist/. ../dist/
						# Without the tauri CLI, the devUrl makes the binary expect a
						# running Vite dev server on localhost:1420. Remove it so the
						# app loads the embedded frontend instead.
						substituteInPlace tauri.conf.json \
							--replace-fail '"devUrl": "http://localhost:1420",' ""
					'';

          cargoLock.lockFile = src + "/src-tauri/Cargo.lock";

					doCheck = false;

          nativeBuildInputs = with pkgs; [
            pkg-config
            wrapGAppsHook3
          ];

          buildInputs = with pkgs; [
            gtk3
            webkitgtk_4_1
            libsoup_3
            glib
            glib-networking
            dbus
            librsvg
          ];

          # silence tauri-build's attempt to fetch things / run extra tooling
          env = {
            TAURI_CONFIG = builtins.toJSON {
              build = {
                beforeBuildCommand = "";
                frontendDist = "../dist";
              };
            };
          };

          meta = with pkgs.lib; {
            description = "Free, open-source chemical structure drawing editor";
            homepage = "https://github.com/SamChemMan/Octet-Draw";
            license = licenses.asl20;
            mainProgram = "octet";
            platforms = platforms.linux;
          };
        };

      in
      {
        packages = {
          default = octet-draw;
          octet-draw = octet-draw;
        };

        apps.octet-draw = flake-utils.lib.mkApp {
          drv = octet-draw;
          name = "octet";
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs
            cargo
            rustc
            rust-analyzer
            pkg-config
            glib
            gtk3
            webkitgtk_4_1
            libsoup_3
            glib-networking
          ];
          # for `npm install && npm run tauri dev`
          shellHook = ''
            export PKG_CONFIG_PATH="${pkgs.webkitgtk_4_1.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
          '';
        };
      });
}
