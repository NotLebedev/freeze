{ lib, pkgs, system, ... }:

lib.wrapScript {
  package = lib.buildNuPackage {
    name = "emoji-picker";
    version = "0.0.1";
    src = ./.;
    packages = with pkgs; [
      wofi
      wtype
    ];
    inherit system;
  };
  script = "emoji-picker/mod.nu";
  binName = "emoji-picker";
}
