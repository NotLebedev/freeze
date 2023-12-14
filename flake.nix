{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nuenv.url = "github:NotLebedev/nuenv/nu-87";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nuenv, flake-utils }:
    {
      overlays = rec {
        default = freeze;

        freeze = final: prev:
          let
            pkgs = prev.extend nuenv.overlays.default;
            lib = import ./lib { };
          in
          {
            nushell-freeze = {
              # Create a package from nushell files
              #
              # name: name of nushell package. Available to `use` commands under this name
              #     (e.g. for `name = "myPackage"` `use myPackage/myScipt *`)
              # src: source file or directory to create package from. If directory is specified
              #     its contents are copied to `lib/nushell/<name>/` directory 
              # packages: optinal list of packages used by this package. Binary packages (those
              #     with files in `bin/` directory) and other freeze packages are supported.
              #     other will be ignored 
              buildPackage = lib.buildNuPackage pkgs.system pkgs;

              # Create a nushell wrapper with no user configuration
              # and specified packages in $env.NU_LIB_DIRS
              withPackages = lib.withPackages pkgs.system pkgs;

              # Turn nushell script into a binary. Wraps given script, located in package, 
              # as "bin/<binName>"
              #
              # package: a package containing "lib/nushell" (made by buildNuPackage)
              # scriptName: identificator of script to run in format "<package>/<file name>".
              #     Note that <file name> must be appended even if it is mod.nu, this is a limitation
              #     on part of nushell, while it searches through -I arguments it does not expand
              #     search for mod.nu for directories like `use` does
              # binName: name of the resulting binary in "bin/" of derivation
              wrapScript = lib.wrapScript pkgs.system pkgs;
            } // (prev.nushell-freeze or { });
          };

        packages = final: prev:
          let
            pkgs = prev.extend self.overlays.default;
          in
          {
            nushell-freeze = {
              packages = import ./packages { pkgs = pkgs; };
            } // (prev.nushell-freeze or { });
          };
      };

      homeManagerModule = (import ./lib {}).homeManagerModule;
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.freeze
          ];
        };
      in
      rec {
        defaultPackage = packages.script;
        packages = {
          withTestPackages = pkgs.nushell-freeze.withPackages [
            self.packages.${system}.script
            self.packages.${system}.dependency
          ];

          script = pkgs.nushell-freeze.buildPackage {
            name = "test";
            src = ./examples/script;
            packages = with pkgs; [
              cowsay
              ddate
              ripgrep
              self.packages.${system}.dependency
            ];
          };

          dependency = pkgs.nushell-freeze.buildPackage {
            name = "dependency";
            src = ./examples/dep;
            packages = with pkgs; [
              lolcat
            ];
          };

          helloWrapped = pkgs.nushell-freeze.wrapScript {
            package = pkgs.nushell-freeze.buildPackage {
              name = "wrapScript";
              src = ./examples/wrapScript;
            };
            script = "wrapScript/mod.nu";
            binName = "hello";
          };

          emoji-picker = import ./examples/emoji-picker pkgs;
        } // (import ./packages { pkgs = pkgs; });
      }
    );
}
