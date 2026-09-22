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
in
{
  _class = "darwin";
  imports = [ ./options.nix ];
  config = lib.modules.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "pared requires macOS.";
      }
    ];
    environment.etc."pared/policy.json".source = policyFile;
    environment.systemPackages = [ cfg.package ];
    system.defaults.CustomUserPreferences = policy.userPreferences;
    environment.etc."pared/disable-apple-intelligence.mobileconfig".text = import ../profile.nix {
      inherit lib policy;
    };
    environment.etc."pared/declarations.json".text = builtins.toJSON (
      import ../declarations.nix { inherit lib policy; }
    );
    system.activationScripts.postActivation.text = lib.mkIf cfg.cleanupOnActivation (
      lib.mkAfter (
        import ../cleanup.nix {
          inherit lib pkgs policyFile;
          package = cfg.package;
          stateDirectory = "/var/db/pared";
          profilePath = "/etc/pared/disable-apple-intelligence.mobileconfig";
        }
      )
    );
  };
}
