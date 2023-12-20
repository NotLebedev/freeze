{ pkgs, ... }:

let
  package = pkgs.nushell-freeze.buildPackage {
    name = "package";
    src = ./.;
    packages = with pkgs; [
      jq
    ];
  };
in
pkgs.nuenv.mkDerivation {
  name = "checkScriptScriptDep";
  src = ./.;

  build = ''
    #!/usr/bin/env nu
    use ${package}/lib/nushell/package

    package

    mkdir $env.out
  '';
}

