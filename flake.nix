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
          , mainScript
          , system
          , packages ? []
          , ...
          }: pkgs.nuenv.mkDerivation {
            inherit name;
            inherit version;
            inherit src;
            inherit system;
            inherit packages;
            inherit mainScript;

            mainScriptName = builtins.baseNameOf mainScript;
            copy = src;
            build = ''
              #!/usr/bin/env nu
              let out = $env.out
              let lib_target = $'($out)/lib/nushell'
              mkdir $'($out)/lib'

              let source = open --raw $env.mainScript

              # def --env is not allowed, because it will polute outer
              # environment with path of package
              let main_head_regex = 'def\s+?main\s+\[[^]]*\][^{]*{'
              let extern_head_regex = 'export\s+def\s+\S+\s+\[[^]]*\][^{]*{'

              # Match either `def main [...] {` or any `export def ... [...] {` 
              let patch_head_regex = $"\(?:($main_head_regex)\)|\(?:($extern_head_regex)\)"
              let add_set_env = "$0\n__set_env"
              let patched_with_call = $source | str replace -a -r $patch_head_regex $add_set_env

              let add_path = '${pkgs.lib.makeBinPath packages}' | split row :

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
              let main_script_patched = [$patched_with_call $set_env_func] | str join
              
              cp -r $env.copy $lib_target
              rm $'($lib_target)/($env.mainScriptName)'
              $main_script_patched | save $'($lib_target)/($env.mainScriptName)'
            '';
          };
      };

    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      rec {
        defaultPackage = packages.script;
        packages.script = self.lib.buildNuPackage {
          name = "test";
          version = "0.0.1";
          src = ./.;
          inherit system;
          packages = with pkgs; [ cowsay ddate ripgrep ];
          mainScript = ./test.nu;
        };
      }
    );
}
