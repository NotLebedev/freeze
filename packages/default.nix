{ pkgs, ... }:

{
  # All scripts in https://github.com/nushell/nu_scripts as one package
  nu_scripts = pkgs.nushell-freeze.buildPackage {
    name = "nu_scripts";
    src = pkgs.fetchFromGitHub {
      owner = "nushell";
      repo = "nu_scripts";
      rev = "a4cceb8a0b6295fb0b89fb806b1aebefa2d243c9";
      hash = "sha256-8ivtH+mNFf1kbMNn9lmuwCLqG9zE9Z6wsqlwwfHbT98=";
    };
  };

  # Package a specific scripts in https://github.com/nushell/nu_scripts
  # name: string name to give to resulting package
  # path: string path in repo to specific script file or directory 
  #     (e.g. `"custom-completions/git/git-completions.nu"`)
  from_nu_scripts = name: path: pkgs.nushell-freeze.buildPackage {
    name = name;
    src = (pkgs.fetchFromGitHub {
      owner = "nushell";
      repo = "nu_scripts";
      rev = "a4cceb8a0b6295fb0b89fb806b1aebefa2d243c9";
      hash = "sha256-8ivtH+mNFf1kbMNn9lmuwCLqG9zE9Z6wsqlwwfHbT98=";
    }) + "/${path}";
  };

  # nu-git-manager part of https://github.com/amtoine/nu-git-manager as a package
  nu-git-manager = pkgs.nushell-freeze.buildPackage {
    name = "nu-git-manager";
    src = (pkgs.fetchFromGitHub {
      owner = "amtoine";
      repo = "nu-git-manager";
      rev = "c2242b4149a6cfec829b04a49c02f07b3a04cfe8";
      hash = "sha256-a6GliOzcbcOQQ5FLoHHcm3BRSJsab2vemXR2c2BhQzI=";
    }) + "/src/nu-git-manager";
  };

  # nu-git-manager-sugar part of https://github.com/amtoine/nu-git-manager as a package
  nu-git-manager-sugar = pkgs.nushell-freeze.buildPackage {
    name = "nu-git-manager-sugar";
    src = (pkgs.fetchFromGitHub {
      owner = "amtoine";
      repo = "nu-git-manager";
      rev = "c2242b4149a6cfec829b04a49c02f07b3a04cfe8";
      hash = "sha256-a6GliOzcbcOQQ5FLoHHcm3BRSJsab2vemXR2c2BhQzI=";
    }) + "/src/nu-git-manager-sugar";
  };
}
