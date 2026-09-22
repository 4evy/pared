{
  pkgs,
  lib,
  revision ? "main",
}:
let
  root = toString ./.. + "/";
  evaluated = lib.modules.evalModules {
    modules = [
      ../nix/modules/options.nix
      (pkgs.path + "/nixos/modules/misc/assertions.nix")
    ];
    specialArgs = { inherit pkgs; };
  };
in
pkgs.nixosOptionsDoc {
  options = removeAttrs evaluated.options [ "_module" ];
  transformOptions =
    option:
    option
    // {
      declarations = map (declaration: {
        name = "<pared/${lib.strings.removePrefix root (toString declaration)}>";
        url = "https://github.com/4evy/pared/blob/${revision}/${lib.strings.removePrefix root (toString declaration)}";
      }) option.declarations;
    };
}
