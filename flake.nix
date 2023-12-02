{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nuenv.url = "github:NotLebedev/nuenv/nu-87";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nuenv, flake-utils }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ nuenv.overlays.nuenv ];
      };
    in
    {
      lib = {
        buildNuPackage =
          { name
          , version
          , src
          , system
          , packages ? [ ]
          , ...
          }: pkgs.nuenv.mkDerivation {
            inherit name;
            inherit version;
            inherit src;
            inherit system;
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
                    ${pkgs.coreutils-full}/bin/ln -s $import $'($d)/($link_name)' 
                  }
                }
              }
            '';
          };
      };

    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      rec {
        defaultPackage = packages.script;
        packages = {
          script = self.lib.buildNuPackage {
            name = "test";
            version = "0.0.1";
            src = ./examples/script;
            inherit system;
            packages = with pkgs; [
              cowsay
              ddate
              ripgrep
              self.packages.${system}.dependency
            ];
          };

          dependency = self.lib.buildNuPackage {
            name = "dependency";
            version = "0.0.1";
            src = ./examples/dep;
            inherit system;
            packages = with pkgs; [
              lolcat
            ];
          };
        };
      }
    );
}
