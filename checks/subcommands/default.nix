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
  use ${package}/lib/nushell/package *

  sub
  sub command1
  sub command2
  sub command3

  mkdir $env.out
''
