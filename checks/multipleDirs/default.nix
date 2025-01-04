{ pkgs, ... }:

let
  dep = pkgs.nushell-freeze.buildPackage {
    name = "dep";
    src = ./dep.nu;
  };

  package = pkgs.nushell-freeze.buildPackage {
    name = "package";
    src = ./src;
    packages = [ dep ];
  };
in
''
  #!/usr/bin/env nu
  use ${package}/lib/nushell/package *

  test

  mkdir $env.out
''
