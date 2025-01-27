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

  assert equal ({a: {b: qwe}} | to json | simple-pipe) qwe
  assert equal ({a: qwe b: 5} | pipe-complex) {c: qwe d: 3}
  assert equal ('qwe' | pipe-let) 'qwe'

  mkdir $env.out
''
