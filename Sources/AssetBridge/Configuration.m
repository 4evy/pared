#import "ConfigurationInternal.h"

#import "BridgeInternal.h"

id<ParedConfigurationManagerAPI> ParedConfigurationManager(void) {
  Class type = NSClassFromString(@"UAFConfigurationManager");
  return ParedHasMethod(type, @selector(defaultManager),
                        @protocol(ParedConfigurationManagerAPI))
             ? [(id<ParedConfigurationManagerAPI>)type defaultManager]
             : nil;
}

id<ParedAssetSetConfigurationAPI>
ParedAssetSetWithManager(id<ParedConfigurationManagerAPI> manager,
                         NSString *name) {
  if (!ParedNonemptyString(name)) {
    return nil;
  }
  return ParedHasMethod(manager, @selector(getAssetSet:),
                        @protocol(ParedConfigurationManagerAPI))
             ? [manager getAssetSet:name]
             : nil;
}

static id<ParedAssetSetConfigurationAPI> ParedAssetSet(NSString *name) {
  return ParedAssetSetWithManager(ParedConfigurationManager(), name);
}

// Apple's validator checks usage names but misses some value restrictions and
// alias contents. Check those here so asset selection cannot silently discard
// an unsupported value
BOOL ParedEnabledUsagesMatchConfiguration(
    ParedAssetSetUsages *sets, id<ParedConfigurationManagerAPI> manager) {
  for (NSString *name in sets) {
    id<ParedAssetSetConfigurationAPI> set =
        ParedAssetSetWithManager(manager, name);
    if (!ParedHasDeclaredMethods(set, @protocol(ParedAssetSetUsageAPI))) {
      return NO;
    }
    id names = [set usageTypes];
    id restrictions = [set usageValues];
    if (!ParedHasNonemptyStrings(names) ||
        (restrictions && ![restrictions isKindOfClass:NSDictionary.class])) {
      return NO;
    }
    for (NSString *usage in sets[name]) {
      id values = restrictions[usage];
      if (![names containsObject:usage] ||
          (values && (!ParedHasNonemptyStrings(values) ||
                      ![values containsObject:@"ENABLED"]))) {
        return NO;
      }
    }
  }
  return YES;
}

ParedAssetSetUsages *
ParedResolveAliasWithManager(id<ParedConfigurationManagerAPI> manager,
                             NSString *alias, NSString *value) {
  if (!ParedNonemptyString(alias) || ![value isKindOfClass:NSString.class] ||
      !ParedHasMethod(
          manager, @selector(getAssetSetUsagesForUsageAlias:usageAliasValue:),
          @protocol(ParedConfigurationManagerAPI))) {
    return nil;
  }
  // Copy the expansion so callers cannot mutate Apple's configuration
  return ParedCopyAssetSetUsages(
      [manager getAssetSetUsagesForUsageAlias:alias usageAliasValue:value]);
}

NSString *ParedAssetTypeForSet(NSString *name) {
  id<ParedAssetSetConfigurationAPI> set = ParedAssetSet(name);
  if (!ParedHasMethod(set, @selector(autoAssetType),
                      @protocol(ParedAssetSetConfigurationAPI))) {
    return nil;
  }
  id value = [set autoAssetType];
  return ParedNonemptyString(value) ? [value copy] : nil;
}

NSArray<NSString *> *ParedUsageTypesForSet(NSString *name) {
  id<ParedAssetSetConfigurationAPI> set = ParedAssetSet(name);
  if (!ParedHasMethod(set, @selector(usageTypes),
                      @protocol(ParedAssetSetConfigurationAPI))) {
    return nil;
  }
  id value = [set usageTypes];
  if (!ParedHasNonemptyStrings(value)) {
    return nil;
  }
  return [[NSArray alloc] initWithArray:value copyItems:YES];
}

NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
ParedResolveUsageAlias(NSString *alias, NSString *value) {
  // Aliases can include dependencies in other asset sets. Callers must check
  // the expanded set names against their intended download scope
  return ParedResolveAliasWithManager(ParedConfigurationManager(), alias,
                                      value);
}
