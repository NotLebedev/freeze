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
  use std assert
  use ${package}/lib/nushell/package *

  test0
  test1
  test2
  test3
  test4
  test5

  mkdir $env.out
''
