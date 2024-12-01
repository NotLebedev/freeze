{ pkgs, inputs, ... }:

{
  # All scripts in https://github.com/nushell/nu_scripts as one package
  nu_scripts = pkgs.nushell-freeze.buildPackage {
    name = "nu_scripts";
    src = inputs.nu_scripts;
  };

  # Package a specific scripts in https://github.com/nushell/nu_scripts
  # name: string name to give to resulting package
  # path: string path in repo to specific script file or directory 
  #     (e.g. `"custom-completions/git/git-completions.nu"`)
  from_nu_scripts =
    name: path:
    pkgs.nushell-freeze.buildPackage {
      name = name;
      src = inputs.nu_scripts + "/${path}";
    };
}
