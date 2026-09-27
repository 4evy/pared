{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.pared = {
    enable = lib.options.mkEnableOption "pared Apple Intelligence restrictions and preferences";
    cleanupOnActivation = lib.options.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        During activation, remove models whose known consumers are all disabled.
        Skip cleanup when the policy matches the last successful cleanup.
        The cleanup record is stored in
        /var/db/pared/cleaned-policy.json for nix-darwin, or
        $XDG_STATE_HOME/pared/cleaned-policy.json for Home Manager.
        Failures retry on the next activation. Install the generated
        configuration profile to block future downloads.
      '';
    };
    package = lib.options.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../package.nix { };
      defaultText = lib.options.literalExpression "pkgs.callPackage <pared/nix/package.nix> { }";
      description = "The pared executable package.";
    };
    defaultState = lib.options.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = false;
      description = ''
        State for features not listed in features. true enables a feature,
        false disables it, and null omits it from generated settings.
        The default disables every feature without an explicit override.
      '';
    };
    features = lib.options.mkOption {
      default = { };
      description = ''
        Override defaultState for individual features. true enables a feature,
        false disables it, and null leaves it unmanaged. Changing a value to
        null does not remove preferences written earlier. Rebuild and install
        the replacement profile to update managed restrictions and download
        blocks; rebuilding alone does not replace an installed profile.
      '';
      type = lib.types.submodule {
        options = lib.attrsets.mapAttrs (
          _: feature:
          lib.options.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = config.programs.pared.defaultState;
            defaultText = lib.options.literalExpression "config.programs.pared.defaultState";
            description = feature.description;
          }
        ) (lib.trivial.importJSON ../../Sources/Pared/Resources/catalog.json).features;
      };
    };
  };
}
