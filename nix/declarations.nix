{
  lib,
  policy ? import ./policy.nix { inherit lib; },
}:
policy.declarations
