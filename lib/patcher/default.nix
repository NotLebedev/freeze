{ craneLib, ... }:

let
  src = craneLib.cleanCargoSource (craneLib.path ./.);

  commonArgs = {
    inherit src;
    strictDeps = true;

    buildInputs = [ ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  my-crate = craneLib.buildPackage (commonArgs // {
    inherit cargoArtifacts;
    doCheck = false;
  });
in
{
  checks = {
    inherit my-crate;

    my-crate-clippy = craneLib.cargoClippy (commonArgs // {
      inherit cargoArtifacts;
      cargoClippyExtraArgs = "--all-targets -- --deny warnings";
    });

    my-crate-doc = craneLib.cargoDoc (commonArgs // {
      inherit cargoArtifacts;
    });

    my-crate-fmt = craneLib.cargoFmt {
      inherit src;
    };

    my-crate-nextest = craneLib.cargoNextest (commonArgs // {
      inherit cargoArtifacts;
      partitions = 1;
      partitionType = "count";
    });
  };

  package = my-crate;
}
