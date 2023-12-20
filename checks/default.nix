{ pkgs, ... }:

{
  noDeps = import ./noDeps { inherit pkgs; };
  scriptScriptDep = import ./scriptScriptDep { inherit pkgs; };
  binaryDeps = import ./binaryDeps { inherit pkgs; };
}
