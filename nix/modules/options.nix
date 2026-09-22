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
        Remove models for disabled features once per policy change during
        activation. Successful cleanup is recorded in
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
      description = "Default for features without an override: true enables, false disables, and null leaves unmanaged.";
    };
    features = lib.options.mkOption {
      default = { };
      description = "Per-feature policy: true enables, false disables, and null leaves unmanaged without undoing earlier preferences.";
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
