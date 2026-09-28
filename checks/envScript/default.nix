{ pkgs, ... }:

let
  package = pkgs.nushell-freeze.buildPackage {
    name = "package";
    src = ./.;
    packages = with pkgs; [
      jq
    ];
  };
in
''
  #!/usr/bin/env nu
  use ${package}/lib/nushell/package *
  use std assert

  do {
    let old_path = $env.PATH
    new-var
    # Check that new var is set
    assert ($env.QWE == rty)
    # Check that PATH was not changed after running
    assert ($env.PATH == $old_path)
  }

  do {
    let expected_path = ($env.PATH | append /qwe/qwe)
    add-to-path
    # Check that one entry was added to path
    assert ($env.PATH == $expected_path)
  }

  do {
    clear-path
    assert ($env.PATH == [ ])
  }

  do {
    let old_path = $env.PATH
    one-calls-another
    # Check that PATH was not changed after running
    assert ($env.PATH == $old_path)
  }

  mkdir $env.out
''
