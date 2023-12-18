{ pkgs, ... }:

{
  checks =
    let
      scriptNoDeps = import ./scriptNoDeps { inherit pkgs; };
    in
    {
      inherit scriptNoDeps;
    };
}
