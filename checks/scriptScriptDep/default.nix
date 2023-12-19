{ pkgs, ... }:

let
  dependency0 = pkgs.nushell-freeze.buildPackage {
    name = "dependency0";
    src = ./dependency0.nu;
  };

  dependency1 = pkgs.nushell-freeze.buildPackage {
    name = "dependency1";
    src = ./dependency1.nu;
  };

  # This script depends on two other scripts, which can be `use`d as
  # `use dependency0` and `use dependency1` (according to `name` attribute
  # of their repsective packages)
  package = pkgs.nushell-freeze.buildPackage {
    name = "package";
    src = ./package.nu;
    packages = [
      dependency0
      dependency1
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

