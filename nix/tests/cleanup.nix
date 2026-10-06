{ pkgs }:
let
  inherit (pkgs) lib;
  package = pkgs.writeShellScriptBin "pared" ''
    printf '%s\n' "$*" >> calls
    exit "''${PARED_TEST_EXIT:-0}"
  '';
  cleanup = pkgs.writeShellScript "pared-cleanup-test" (
    import ../cleanup.nix {
      inherit lib pkgs package;
      policyFile = "policy.json";
      stateDirectory = "state with spaces";
      profilePath = "profile.mobileconfig";
    }
  );
in
pkgs.runCommand "pared-cleanup-regression"
  {
    nativeBuildInputs = [ pkgs.swift ];
  }
  ''
    swift ${../../Tests/test_activation.swift} ${cleanup}
    touch "$out"
  ''
