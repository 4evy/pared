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
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 ${../../Tests/test_activation.py} ${cleanup}
    touch "$out"
  ''
