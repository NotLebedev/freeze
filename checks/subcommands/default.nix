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
  name = "subcommands";
  src = ./.;

  build = ''
    #!/usr/bin/env nu
    use ${package}/lib/nushell/package *
    use std assert

    sub
    sub command1
    sub command2
    sub command3

    mkdir $env.out
  '';
}

