{ pkgs, ... }:

{
  noDeps = import ./noDeps { inherit pkgs; };
  scriptDep = import ./scriptDep { inherit pkgs; };
  binaryDeps = import ./binaryDeps { inherit pkgs; };
  pipeSyntax = import ./pipeSyntax { inherit pkgs; };
}
