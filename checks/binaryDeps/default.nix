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
''
  #!/usr/bin/env nu
  use ${package}/lib/nushell/package

  package

  mkdir $env.out
''
