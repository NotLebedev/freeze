{ craneLib, ... }:

let
  src = craneLib.cleanCargoSource (craneLib.path ./.);

  commonArgs = {
    inherit src;
    strictDeps = true;

    buildInputs = [ ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  patcher = craneLib.buildPackage (
    commonArgs
    // {
      inherit cargoArtifacts;
      doCheck = false;
    }
  );
in
{
  checks = {
    inherit patcher;

    patcher-clippy = craneLib.cargoClippy (
      commonArgs
      // {
        inherit cargoArtifacts;
        cargoClippyExtraArgs = "--all-targets -- --deny warnings";
      }
    );

    patcher-fmt = craneLib.cargoFmt {
      inherit src;
    };
  };

  package = patcher;
}
