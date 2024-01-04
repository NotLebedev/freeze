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
  name = "commentsAndStrings";
  src = ./.;

  build = ''
    #!/usr/bin/env nu
    use assert
    use ${package}/lib/nushell/package *

    test0
    test1
    test2
    test3
    test4
    test5

    mkdir $env.out
  '';
}

