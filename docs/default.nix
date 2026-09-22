{
  pkgs,
  revision ? "main",
}:
let
  options = pkgs.callPackage ./options-doc.nix { inherit revision; };
in
{
  json = options.optionsJSON;
  html = pkgs.callPackage ./site.nix {
    inherit revision;
    optionsJSON = options.optionsJSON;
  };
}
