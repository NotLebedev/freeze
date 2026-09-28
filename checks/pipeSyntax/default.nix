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

  assert (({a: {b: qwe}} | to json | simple-pipe) == 'qwe')
  assert (({a: qwe b: 5} | pipe-complex) == {c: qwe d: 3})
  assert (('qwe' | pipe-let) == 'qwe')

  mkdir $env.out
''
