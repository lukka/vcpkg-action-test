{
  description = "Build env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustVersion = "1.66.1";

        rust = pkgs.rust-bin.stable.${rustVersion}.default.override {
          extensions = [
            "rust-src" # rust-analyzer
          ];
        };

        nixLib = nixpkgs.lib;
        craneLib = (crane.mkLib pkgs).overrideToolchain rust;

        # Libraries needed both at compile and runtime
        sharedDeps = with pkgs; [
          dbus
          xorg.libX11
          fontconfig
          udev
          glib
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
        ];

        # Manually simulate a vcpkg installation so that it can link the libaries
        # properly. Borrowed and adapted from: https://github.com/NixOS/nixpkgs/blob/69a35ff92dc404bf04083be2fad4f3643b2152c9/pkgs/applications/networking/remote/rustdesk/default.nix#L51
        vcpkg = pkgs.stdenv.mkDerivation {
          pname = "vcpkg";
          version = "1.0.0";

          unpackPhase =
            let
              vcpkg_target = "x64-linux";

              updates_vcpkg_file = pkgs.writeText "update_vcpkg_my_crate"
                ''
                  Package : libvpx
                  Architecture : ${vcpkg_target}
                  Version : 1.0
                  Status : is installed
                '';
            in
            ''
              mkdir -p vcpkg/.vcpkg-root
              mkdir -p vcpkg/installed/${vcpkg_target}/lib
              mkdir -p vcpkg/installed/vcpkg/updates
              ln -s ${updates_vcpkg_file} vcpkg/installed/vcpkg/status
              mkdir -p vcpkg/installed/vcpkg/info
              touch vcpkg/installed/vcpkg/info/libvpx_1.0_${vcpkg_target}.list
              ln -s ${pkgs.libvpx.out}/lib/* vcpkg/installed/${vcpkg_target}/lib/
            '';

          installPhase = ''
            cp -r vcpkg $out
          '';
        };

        envVars = rec {
          RUST_BACKTRACE = 1;
          MOLD_PATH = "${pkgs.mold.out}/bin/mold";
          RUSTFLAGS = "-Clink-arg=-fuse-ld=${MOLD_PATH} -Clinker=clang";
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          VCPKG_ROOT = "${vcpkg.out}";
        };

        # The main application derivation
        my_crate = craneLib.buildPackage
          ({
            src = nixLib.cleanSourceWith
              {
                src = ./.;
              };

            doCheck = false;

            # cargoBuildCommand = "cargo build";

            buildInputs = with pkgs;
              [
                libvpx
              ]
              ++ sharedDeps
              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ ];

            nativeBuildInputs = with pkgs;
              [
                pkg-config
                cmake
                clang
              ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ ];
          } // envVars);


      in
      {
        checks = {
          # inherit my_crate;
        };

        packages.default = my_crate;

        devShells.rust = pkgs.mkShell {
          nativeBuildInputs = [ rust ];
        };

        devShells.default = my_crate;

        apps.default = flake-utils.lib.mkApp {
          drv = my_crate;
        };
      });
}
