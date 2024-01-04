{ ... }:

{
  buildNuPackage =
    system:
    pkgs:
    { name
    , src
    , packages ? [ ]
    , ...
    }: pkgs.nuenv.mkDerivation {
      inherit name;
      inherit src;
      inherit packages;

      copy = src;
      package_name = name;
      symlinkjoin_path = pkgs.symlinkJoin {
        name = "${name}-symlinkjoin";
        paths = packages;
      };

      # Unfortunately nushell does not have ln command. For now use uutils one
      # for (hopefully) better compat in future
      ln = "${pkgs.uutils-coreutils}/bin/uutils-ln";
      build = builtins.readFile ./build.nu;
    };

  withPackages = system: pkgs: packages:
    let
      joined = pkgs.lib.makeSearchPath "lib/nushell" packages;
      # Replacement is not a whitespace. It is actually a \x1e character
      # aka "record separator"
      replaced = builtins.replaceStrings [ ":" ] [ "" ] joined;
    in
    pkgs.writeShellScriptBin "nu" ''
      ${pkgs.nushell}/bin/nu -n -I "${replaced}" $@
    '';

  wrapScript = system: pkgs: { package, script, binName }:
    let
      scriptFullPath = package + "/lib/nushell/${script}";
    in
    pkgs.writeShellScriptBin binName ''
      ${pkgs.nushell}/bin/nu ${scriptFullPath} $@
    '';

  homeManagerModule = { lib, config, ... }: {
    options.programs.nushell.freeze-packages = with lib; mkOption {
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
