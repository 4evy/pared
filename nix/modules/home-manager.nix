{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pared;
  policy = import ../policy.nix {
    inherit lib;
    inherit (cfg) defaultState features;
  };
  policyFile = pkgs.writeText "pared-policy.json" (builtins.toJSON policy.document);
  cleanup = pkgs.writeShellScript "pared-cleanup" (
    import ../cleanup.nix {
      inherit lib pkgs policyFile;
      package = cfg.package;
      stateDirectory = "${config.xdg.stateHome}/pared";
      profilePath = "${config.xdg.configHome}/pared/disable-apple-intelligence.mobileconfig";
    }
  );
in
{
  _class = "homeManager";
  imports = [ ./options.nix ];
  config = lib.modules.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.pared" pkgs lib.platforms.darwin)
    ];
    xdg.configFile."pared/policy.json".source = policyFile;
    home.packages = [ cfg.package ];
    home.activation.paredCleanup = lib.mkIf cfg.cleanupOnActivation (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${cleanup}
      ''
    );
    targets.darwin.defaults = policy.userPreferences;
    xdg.configFile."pared/disable-apple-intelligence.mobileconfig".text = import ../profile.nix {
      inherit lib policy;
    };
    xdg.configFile."pared/declarations.json".text = builtins.toJSON (
      import ../declarations.nix { inherit lib policy; }
    );
  };
}
