{ pkgs, ... }:

let
  checks = [
    "noDeps"
    "scriptDep"
    "binaryDeps"
    "pipeSyntax"
    "envScript"
    "subcommands"
  ];
in
builtins.listToAttrs (builtins.map
  (check: {
    name = check;
    value = import ./${check} { inherit pkgs; };
  })
  checks
)
