{ pkgs, ... }:

{
  scriptNoDeps = import ./scriptNoDeps { inherit pkgs; };
}
