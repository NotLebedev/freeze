{
  description = "A very basic flake";
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2305.*.tar.gz";
    nuenv.url = "github:DeterminateSystems/nuenv";
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
          , packages
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
              mkdir $out

              let source = (open --raw $env.mainScript)

              let main_head_regex = 'def\s+(?:--env\s+)?main\s+\[[^]]*\][^{]*{'
              let add_set_env = "$0\n__set_env"
              let patched_with_call = ($source | str replace -a $main_head_regex $add_set_env)

              let add_path = '${pkgs.lib.makeBinPath packages}'
              let set_env_func = ('def --env __set_env [] { ' + 
                $" $env.PATH = \($env.PATH | append ($add_path | to nuon)\) }\n")
              let main_script_patched = ([$patched_with_call $set_env_func] | str join)
              
              cp -r $'($env.copy)' $'($out)/bin'
              rm $'($out)/bin/($env.mainScriptName)'
              $main_script_patched | save -f $'($out)/bin/($env.mainScriptName)'
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
          packages = with pkgs; [ cowsay ];
          mainScript = ./test.nu;
        };
      }
    );
}
