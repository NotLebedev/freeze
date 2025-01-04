{ ... }:

{
  buildNuPackage =
    pkgs: patcher:
    {
      name,
      src,
      packages ? [ ],
      ...
    }:
    let
      symlinkjoin_path = pkgs.symlinkJoin {
        name = "${name}-symlinkjoin";
        paths = packages;
      };
    in
    pkgs.stdenv.mkDerivation {
      inherit name;
      inherit src;
      inherit packages;

      phases = [
        "buildPhase"
        "installPhase"
      ];

      buildPhase = "${patcher}/bin/freeze-patcher ${src} ${name} ${symlinkjoin_path}";
      installPhase = ''
        mkdir -p "$out/lib/nushell"
        cp -r build "$out/lib/nushell/${name}"
      '';
    };

  withPackages =
    pkgs: packages:
    let
      joined = pkgs.lib.makeSearchPath "lib/nushell" packages;
      # Replacement is not a whitespace. It is actually a \x1e character
      # aka "record separator"
      replaced = builtins.replaceStrings [ ":" ] [ "" ] joined;
    in
    pkgs.writeShellScriptBin "nu" ''
      ${pkgs.nushell}/bin/nu -n -I "${replaced}" $@
    '';

  wrapScript =
    pkgs:
    {
      package,
      script,
      binName,
    }:
    let
      scriptFullPath = package + "/lib/nushell/${script}";
    in
    pkgs.writeShellScriptBin binName ''
      ${pkgs.nushell}/bin/nu ${scriptFullPath} $@
    '';

  homeManagerModule =
    { lib, config, ... }:
    {
      options.programs.nushell.freeze-packages =
        with lib;
        mkOption {
          type = with types; listOf package;
          default = [ ];
          description = mdDoc "List of freeze packages to add to $env.NU_LIB_DIRS";
        };

      config.programs.nushell.extraEnv =
        let
          dirs = builtins.map (p: p + "/lib/nushell") config.programs.nushell.freeze-packages;
          asNuStrings = builtins.map (p: "'" + p + "'") dirs;
          packagesNuArray = "[ " + (builtins.concatStringsSep " " asNuStrings) + " ]";
        in
        ''
          $env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | append ${packagesNuArray})
        '';
    };
}
