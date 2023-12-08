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

        freeze = final: prev: {
          freeze = {
            buildPackage = self.lib.buildNuPackage prev.system prev;

            # Create a nushell wrapper with no user configuration
            # and specified packages in $env.NU_LIB_DIRS
            withPackages = self.lib.withPackages prev.system prev;

            # Turn nushell script into a binary. Wraps given script, located in package, 
            # as "bin/<binName>"
            #
            # package: a package containing "lib/nushell" (made by buildNuPackage)
            # scriptName: identificator of script to run in format "<package>/<file name>".
            #     Note that <file name> must be appended even if it is mod.nu, this is a limitation
            #     on part of nushell, while it searches through -I arguments it does not expand
            #     search for mod.nu for directories like `use` does
            # binName: name of the resulting binary in "bin/" of derivation
            wrapScript = self.lib.wrapScript prev.system prev;
          };
        };
      };
      lib = {
        buildNuPackage =
          system:
          pkgs:
          { name
          , src
          , packages ? [ ]
          , ...
          }: pkgs.nuenv.mkDerivation {
            inherit name;
            inherit src;
            inherit packages;

            copy = src;
            package_name = name;
            build = ''
              #!/usr/bin/env nu
              let out = $env.out
              let lib_target = $'($out)/lib/nushell/($env.package_name)'
              mkdir $'($out)/lib/nushell'

              # def --env is not allowed, because it will polute outer
              # environment with path of package
              let main_head_regex = 'def\s+?main\s+\[[^]]*\][^{]*{'
              let extern_head_regex = 'export\s+def\s+\S+\s+\[[^]]*\][^{]*{'

              # Match either `def main [...] {` or any `export def ... [...] {` 
              let patch_head_regex = $"\(?:($main_head_regex)\)|\(?:($extern_head_regex)\)"
              let add_set_env = "$0\n__set_env"

              let add_path = '${pkgs.lib.makeBinPath packages}'
                | split row :
                | filter { path exists }

              # __set_env function checks if env was set for current package
              # by checking if PATH ends with dependencies of this package
              # This prevents $add_path added multiple times if exported commands
              # call each other. There may still be a problem if command from
              # one package calls command from another and then back
              let set_env_func = $"def --env __set_env [] { 
                let path = ($add_path | to nuon)
                if \($env.PATH | last \($path | length\)\) != $path {
                  $env.PATH = \($env.PATH | append $path\)
                }
              }"
              log $'Additional $env.PATH = [ ($add_path | str join " ") ]'
              
              cp -r $env.copy $lib_target
              let all_scripts = glob $'($lib_target)/**/*.nu'
              for $f in $all_scripts {
                log $'Patching ($f)'
                let source = open --raw $f
                let patched_with_call = $source | str replace -a -r $patch_head_regex $add_set_env
                let script_patched = [$patched_with_call $set_env_func] | str join
                rm $f
                $script_patched | save -f $f
              }

              let nushell_packages = '${pkgs.lib.makeSearchPath "lib/nushell" packages}'
                | split row :
                | filter { path exists }
                | filter { (ls $in | length) > 0 }

              log $'Nushell scripts forund in dependencies [ ($nushell_packages | str join " ") ]'

              # Find dirs with .nu scripts to add symlinks to nushell script dependencies
              let dirs_with_scripts = $all_scripts | path dirname | uniq
              for $package in $nushell_packages {
                # Each nushell dir may contain more then one package, theoretically
                # Futureproofing, kinda
                let imports = ls $package | get name
                for $import in $imports {
                  let link_name = $import | path basename
                  for $d in $dirs_with_scripts {
                    # Uutils are currently intergrated into nushell so ixpect this to
                    # be easier to replace later
                    ${pkgs.uutils-coreutils}/bin/ln -s $import $'($d)/($link_name)' 
                  }
                }
              }
            '';
          };

        withPackages = system: pkgs: packages:
          let
            joined = pkgs.lib.makeSearchPath "lib/nushell" packages;
            # Replacement is not a whitespace. It is actually a \x1e character
            # aka "record separator"
            replaced = builtins.replaceStrings [ ":" ] [ "" ] joined;
          in
          pkgs.writeShellScriptBin "nu" ''
            ${pkgs.nushell}/bin/nu -n -I "${replaced}" $@
          '';

        wrapScript = system: pkgs: { package, script, binName }:
          let
            scriptFullPath = package + "/lib/nushell/${script}";
          in
          pkgs.writeShellScriptBin binName ''
            ${pkgs.nushell}/bin/nu ${scriptFullPath} $@
          '';
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            nuenv.overlays.nuenv
            self.overlays.freeze
          ];
        };
      in
      rec {
        defaultPackage = packages.script;
        packages = {
          withTestPackages = pkgs.freeze.withPackages [
            self.packages.${system}.script
            self.packages.${system}.dependency
          ];

          script = pkgs.freeze.buildPackage {
            name = "test";
            src = ./examples/script;
            packages = with pkgs; [
              cowsay
              ddate
              ripgrep
              self.packages.${system}.dependency
            ];
          };

          dependency = pkgs.freeze.buildPackage {
            name = "dependency";
            src = ./examples/dep;
            packages = with pkgs; [
              lolcat
            ];
          };

          helloWrapped = pkgs.freeze.wrapScript {
            package = pkgs.freeze.buildPackage {
              name = "wrapScript";
              src = ./examples/wrapScript;
            };
            script = "wrapScript/mod.nu";
            binName = "hello";
          };

          emoji-picker = import ./examples/emoji-picker pkgs;
        };
      }
    );
}
