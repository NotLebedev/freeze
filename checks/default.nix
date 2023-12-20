{ pkgs, ... }:

{
  scriptNoDeps = import ./scriptNoDeps { inherit pkgs; };
  scriptScriptDep = import ./scriptScriptDep { inherit pkgs; };
  binaryDeps = import ./binaryDeps { inherit pkgs; };
}
