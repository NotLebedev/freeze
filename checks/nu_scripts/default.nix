{ pkgs, ... }:

let
  all = pkgs.nushell-freeze.packages.nu_scripts;
  just-temp = pkgs.nushell-freeze.packages.from_nu_scripts "temp" "sourced/temp.nu";
in
''
  #!/usr/bin/env nu
  use std assert

  use ${all}/lib/nushell/nu_scripts/sourced/temp.nu c-to-k
  assert equal (c-to-k 100 -r 0) '100 °C is 373 °K'

  use ${just-temp}/lib/nushell/temp k-to-c
  assert equal (k-to-c 373 -r 0) '373 °K is 100 °C'

  mkdir $env.out
''
