pkgs:

pkgs.nushell-freeze.wrapScript {
  package = pkgs.nushell-freeze.buildPackage {
    name = "emoji-picker";
    version = "0.0.1";
    src = ./.;
    packages = with pkgs; [
      wofi
      wtype
    ];
  };
  script = "emoji-picker/mod.nu";
  binName = "emoji-picker";
}
