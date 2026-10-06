#import "SubscriptionInternal.h"

#import "BridgeInternal.h"
#import "ConfigurationInternal.h"

@implementation ParedAssetSubscription
- (instancetype)initWithNative:(id<ParedSubscriptionAPI>)native
                          name:(NSString *)name {
  if ((self = [super init])) {
    _native = native;
    _name = [name copy];
  }
  return self;
}
@end

// Apple accepts empty scopes and arbitrary usage values; download requests
// need nonempty scopes containing only ENABLED values
static BOOL ParedHasEnabledUsages(ParedAssetSetUsages *sets) {
  // Inputs are validated immutable string maps; distinct values must be exactly
  // ENABLED, which also rejects empty usage maps
  NSSet<NSString *> *enabled = [NSSet setWithObject:@"ENABLED"];
  for (ParedStringValues *usages in sets.objectEnumerator) {
    if (![[NSSet setWithArray:usages.allValues] isEqualToSet:enabled]) {
      return NO;
    }
  }
  return YES;
}

static id<ParedSubscriptionAPI> ParedValidatedNativeSubscription(
    NSString *name, ParedAssetSetUsages *assetSetUsages,
    ParedStringValues *usageAliases, id<ParedConfigurationManagerAPI> manager,
    NSError **error) {
  Class type = NSClassFromString(@"UAFAssetSetSubscription");
  Method initializer = class_getInstanceMethod(
      type, @selector(initWithName:assetSets:usageAliases:));
  if (!manager || !initializer ||
      !ParedMethodMatches(initializer,
                          @selector(initWithName:assetSets:usageAliases:),
                          @protocol(ParedSubscriptionAPI), YES) ||
      !ParedHasMethod(type, @selector(supportsSecureCoding),
                      @protocol(NSSecureCoding)) ||
      !ParedInstancesHaveDeclaredMethods(type, @protocol(NSCoding)) ||
      ![(id<ParedSubscriptionAPI>)type supportsSecureCoding]) {
    ParedSetError(error, @"Required subscription initializer or secure coding "
                         @"interface is unavailable");
    return nil;
  }
  id<ParedSubscriptionAPI> native =
      [(id<ParedSubscriptionAPI>)[type alloc] initWithName:name
                                                 assetSets:assetSetUsages
                                              usageAliases:usageAliases];
  if (![native isKindOfClass:type] ||
      !ParedHasMethod(native, @selector(isValid:error:),
                      @protocol(ParedSubscriptionAPI))) {
    ParedSetError(error,
                  @"Required subscription validation interface is unavailable");
    return nil;
  }
  if (!ParedHasDeclaredMethods(native, @protocol(ParedSubscriptionValuesAPI))) {
    ParedSetError(error,
                  @"Required subscription value interface is unavailable");
    return nil;
  }
  // A compatible signature does not prove the initializer kept our values
  // Check what will be serialized before accepting the subscription
  id storedName = [native name];
  id storedSets = [native assetSets];
  id storedAliases = [native usageAliases];
  if (![storedName isKindOfClass:NSString.class] ||
      ![storedName isEqualToString:name] ||
      ![storedSets isKindOfClass:NSDictionary.class] ||
      ![storedSets isEqualToDictionary:assetSetUsages] ||
      ![storedAliases isKindOfClass:NSDictionary.class] ||
      ![storedAliases isEqualToDictionary:usageAliases] ||
      [native expiration]) {
    ParedSetError(error, @"Apple returned unsupported subscription values");
    return nil;
  }
  // Validate replacements before unsubscribing so invalid input leaves existing
  // requests intact. Start with a fresh error because Apple may chain it
  NSError *validationError = nil;
  if (![native isValid:manager error:&validationError] || validationError) {
    if (validationError) {
      ParedSetReturnedError(error, validationError);
    } else {
      ParedSetError(error, @"Apple rejected the download subscription");
    }
    return nil;
  }
  return native;
}

ParedAssetSubscription *ParedSubscription(NSString *name,
                                          ParedAssetSetUsages *assetSetUsages,
                                          ParedStringValues *usageAliases,
                                          NSError **error) {
  if (!ParedNonemptyString(name)) {
    ParedSetError(error, @"A download subscription requires a nonempty name");
    return nil;
  }
  name = [name copy];
  assetSetUsages = ParedCopyAssetSetUsages(assetSetUsages);
  usageAliases = ParedCopyStringValues(usageAliases);
  if (!assetSetUsages || !usageAliases ||
      (assetSetUsages.count == 0 && usageAliases.count == 0) ||
      !ParedHasEnabledUsages(assetSetUsages)) {
    ParedSetError(error,
                  @"A download subscription requires a name and nonempty "
                  @"ENABLED usages or aliases");
    return nil;
  }
  id<ParedConfigurationManagerAPI> manager = ParedConfigurationManager();
  if (!manager) {
    ParedSetError(error, @"Download configuration interface is unavailable");
    return nil;
  }
  // Check the configuration before calling Apple's validator, which assumes its
  // getters and collection contents are valid
  if (!ParedEnabledUsagesMatchConfiguration(assetSetUsages, manager)) {
    ParedSetError(error, @"Download usages no longer permit ENABLED values");
    return nil;
  }
  for (NSString *alias in usageAliases) {
    ParedAssetSetUsages *resolved =
        ParedResolveAliasWithManager(manager, alias, usageAliases[alias]);
    if (resolved.count == 0 || !ParedHasEnabledUsages(resolved) ||
        !ParedEnabledUsagesMatchConfiguration(resolved, manager)) {
      ParedSetError(
          error, @"Download alias did not resolve to supported ENABLED usages");
      return nil;
    }
  }
  id<ParedSubscriptionAPI> native = ParedValidatedNativeSubscription(
      name, assetSetUsages, usageAliases, manager, error);
  if (!native) {
    return nil;
  }
  return [[ParedAssetSubscription alloc] initWithNative:native name:name];
}
