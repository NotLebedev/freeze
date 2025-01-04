{ pkgs, ... }:

let
  checks = [
    "noDeps"
    "scriptDep"
    "binaryDeps"
    "pipeSyntax"
    "envScript"
    "subcommands"
    "commentsAndString"
    "nu_scripts"
    "multipleDirs"
  ];

  nu = "${pkgs.nushell}/bin/nu";

  mkCheck =
    { name, build }:
    pkgs.stdenv.mkDerivation {
      inherit name;

      phases = [ "buildPhase" ];

      CMD = build;

      buildPhase = ''${nu} -c "$CMD"'';
    };
in
builtins.listToAttrs (
  builtins.map (check: {
    name = check;
    value = mkCheck {
      name = check;
      build = import ./${check} { inherit pkgs; };
    };
  }) checks
)
