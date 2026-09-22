{
  lib,
  defaultState ? false,
  features ? { },
}:
let
  catalog = lib.trivial.importJSON ../Sources/Pared/Resources/catalog.json;
  unknownFeatures = builtins.attrNames (removeAttrs features (builtins.attrNames catalog.features));
  validState = value: value == null || builtins.isBool value;
  encodeState =
    value:
    if value == null then
      "unmanaged"
    else if value then
      "enabled"
    else
      "disabled";
  state = name: features.${name} or defaultState;
  managed = lib.attrsets.filterAttrs (name: _: state name != null) catalog.features;
  managedFeatures = lib.attrsets.mapAttrsToList (name: feature: {
    inherit feature;
    enabled = state name;
  }) managed;
  # Preferences and declarations share nested domains/groups, so merge recursively
  merge = lib.lists.foldl' lib.attrsets.recursiveUpdate { };
  userPreferences = merge (
    lib.lists.concatMap (
      { feature, enabled }:
      map (preference: {
        ${preference.domain}.${preference.key} = enabled != preference.inverted;
      }) feature.preferences
    ) managedFeatures
  );
  blockedAssetSets = builtins.filter (
    assetSet:
    let
      consumers = lib.attrsets.filterAttrs (
        _: feature: builtins.elem assetSet feature.assetSets
      ) catalog.features;
    in
    consumers != { } && builtins.all (name: state name == false) (builtins.attrNames consumers)
  ) (builtins.attrNames catalog.assetTypes);
  downloadPreferences = lib.attrsets.optionalAttrs (blockedAssetSets != [ ]) {
    ${catalog.downloadBlocking.domain} = builtins.listToAttrs (
      map (assetSet: {
        name = catalog.downloadBlocking.keyPrefix + catalog.assetTypes.${assetSet};
        value = catalog.downloadBlocking.url;
      }) blockedAssetSets
    );
  };
  restrictions = lib.attrsets.concatMapAttrs (
    name: feature: lib.attrsets.genAttrs feature.restrictions (_: state name)
  ) managed;
  declarationGroups = merge (
    lib.lists.concatMap (
      { feature, enabled }:
      map (
        path: lib.attrsets.setAttrByPath (lib.strings.splitString "." path) enabled
      ) feature.declarations
    ) managedFeatures
  );
  declaration = group: type: {
    Type = "com.apple.configuration.${type}.settings";
    Identifier = "org.pared.${type}";
    Payload = declarationGroups.${group};
  };
in
assert lib.asserts.assertMsg (
  unknownFeatures == [ ]
) "pared: unknown policy features: ${lib.strings.concatStringsSep ", " unknownFeatures}";
assert lib.asserts.assertMsg (validState defaultState)
  "pared: defaultState must be true, false, or null";
assert lib.asserts.assertMsg (builtins.all validState (
  builtins.attrValues features
)) "pared: feature states must be true, false, or null";
{
  inherit userPreferences restrictions;
  managedPreferences = lib.attrsets.recursiveUpdate userPreferences downloadPreferences;
  document = {
    schemaVersion = 1;
    defaultState = encodeState defaultState;
    features = lib.attrsets.mapAttrs (_: encodeState) features;
  };
  declarations =
    lib.lists.optional (declarationGroups ? intelligence) (declaration "intelligence" "intelligence")
    ++ lib.lists.optional (declarationGroups ? external) (
      declaration "external" "external-intelligence"
    );
}
