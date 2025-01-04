{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nuenv = {
      url = "github:NotLebedev/nuenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
    nu_scripts = {
      url = "github:nushell/nu_scripts";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nuenv,
      flake-utils,
      crane,
      ...
    }@inputs:
    {
      overlays = rec {
        default = freeze;

        freeze =
          final: prev:
          let
            pkgs = prev.extend nuenv.overlays.default;
            craneLib = crane.mkLib pkgs;
            patcher = import ./lib/patcher { inherit craneLib; };
            lib = import ./lib { };
          in
          {
            nushell-freeze = {
              # Create a package from nushell files
              #
              # name: name of nushell package. Available to `use` commands under this name
              #     (e.g. for `name = "myPackage"` `use myPackage/myScipt *`)
              # src: source file or directory to create package from.
              #     If directory is specified its contents are copied to
              #     `lib/nushell/<name>/` directory
              #     If a file is specified it is copied (and renamed) to
              #     `lib/nushell/<name>/mod.nu`
              # packages: optinal list of packages used by this package. Binary packages (those
              #     with files in `bin/` directory) and other freeze packages are supported.
              #     other will be ignored
              buildPackage = lib.buildNuPackage pkgs patcher.package;

              # Create a nushell wrapper with no user configuration
              # and specified packages in $env.NU_LIB_DIRS
              withPackages = lib.withPackages pkgs;

              # Turn nushell script into a binary. Wraps given script, located in package,
              # as "bin/<binName>"
              #
              # package: a package containing "lib/nushell" (made by buildNuPackage)
              # scriptName: identificator of script to run in format "<package>/<file name>".
              #     Note that <file name> must be appended even if it is mod.nu, this is a limitation
              #     on part of nushell, while it searches through -I arguments it does not expand
              #     search for mod.nu for directories like `use` does
              # binName: name of the resulting binary in "bin/" of derivation
              wrapScript = lib.wrapScript pkgs;
            } // (prev.nushell-freeze or { });
          };

        packages =
          final: prev:
          let
            pkgs = prev.extend self.overlays.default;
          in
          {
            nushell-freeze = {
              packages = import ./packages {
                pkgs = pkgs;
                inputs = inputs;
              };
            } // (prev.nushell-freeze or { });
          };
      };

      homeManagerModule = (import ./lib { }).homeManagerModule;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.freeze
            self.overlays.packages
            nuenv.overlays.default
          ];
        };
        craneLib = crane.mkLib pkgs;
        patcher = import lib/patcher { inherit craneLib; };
      in
      {
        checks = import ./checks { inherit pkgs; } // patcher.checks;
        devShells.default = craneLib.devShell {
          checks = patcher.checks;

          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          packages = with pkgs; [
            rust-analyzer
          ];
        };
      }
    );
}
