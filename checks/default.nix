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
  ];
in
builtins.listToAttrs (
  builtins.map (check: {
    name = check;
    value = import ./${check} { inherit pkgs; };
  }) checks
)
