{ pkgs, ... }:

# A simple example of packaging scipts
let
  # Package can be made from a single file. In this
  # case it is copied (and renamed) to `$out/lib/nushell/<name>/mod.nu`
  buildFile = pkgs.nushell-freeze.buildPackage {
    name = "noDeps";
    src = ./script.nu;
  };

  # Package can be made from an entire directory. In this
  # case all of its contents are copied to `$out/lib/nushell/<name>/`
  buildDir = pkgs.nushell-freeze.buildPackage {
    name = "noDeps";
    src = ./.;
  };
in
''
  #!/usr/bin/env nu
  use std assert

  do {
    # Just like any other derivation it can be embedded directly into
    # scripts specified in nushell expressions
    use "${buildDir}/lib/nushell/noDeps/script.nu"
    if ('World' | script greet) != 'Hello, World!' {
      error make { msg: 'Incorrect output of script'}
    }
  }

  do {
    # As noted single file is automatically renamed to mod.nu
    # in this case it is imported by name of parent firectory
    use "${buildFile}/lib/nushell/noDeps"
    if ('World' | noDeps greet) != 'Hello, World!' {
      error make { msg: 'Incorrect output of script'}
    }
  }

  # Check that fiels are not modified without binary dependendcies
  assert equal (open ${./script.nu}) (open ${buildDir}/lib/nushell/noDeps/script.nu)
  assert equal (open ${./script.nu}) (open ${buildFile}/lib/nushell/noDeps/mod.nu)
  mkdir $env.out
''
