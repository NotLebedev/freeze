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
pkgs.nuenv.mkDerivation {
  name = "multipleDirs";
  src = ./.;

  build = ''
    #!/usr/bin/env nu
    use ${package}/lib/nushell/package *

    test

    mkdir $env.out
  '';
}
