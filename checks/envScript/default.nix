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
pkgs.nuenv.mkDerivation {
  name = "envScript";
  src = ./.;

  build = ''
    #!/usr/bin/env nu
    use ${package}/lib/nushell/package *
    use assert

    do {
      let old_path = $env.PATH
      new-var
      # Check that new var is set
      assert equal $env.QWE rty
      # Check that PATH was not changed after running
      assert equal $env.PATH $old_path
    }

    do {
      let expected_path = ($env.PATH | append /qwe/qwe)
      add-to-path
      # Check that one entry was added to path
      assert equal $env.PATH $expected_path
    }

    do {
      clear-path
      assert equal $env.PATH [ ]
    }

    do {
      let old_path = $env.PATH
      one-calls-another
      # Check that PATH was not changed after running
      assert equal $env.PATH $old_path
    }

    mkdir $env.out
  '';
}

