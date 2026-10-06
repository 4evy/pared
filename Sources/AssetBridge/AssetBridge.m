#import "AssetBridge.h"

#import <objc/runtime.h>

#include <string.h>

// Local protocols describe private call signatures without requiring Apple's
// objects to conform to them; check runtime encodings before casting because
// selector presence alone does not establish a compatible call signature
@protocol ParedConfigurationManagerAPI
+ (id)defaultManager;
- (id)getAssetSet:(NSString *)name;
- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)
    getAssetSetUsagesForUsageAlias:(NSString *)alias
                   usageAliasValue:(NSString *)value;
@end

// getAssetSet: returns UAFAssetSetConfiguration, not the UAFAssetSet class
// used to access mapped assets; usages are string names, not usage values
@protocol ParedAssetSetAPI
- (NSString *)autoAssetType;
- (NSArray<NSString *> *)usageTypes;
@end

// The subscriber identity belongs to the operation dictionary, not this object
@protocol ParedSubscriptionAPI <NSObject, NSSecureCoding>
- (instancetype)initWithName:(NSString *)name
                   assetSets:(NSDictionary *)sets
                usageAliases:(NSDictionary *)aliases;
- (BOOL)isValid:(id)configurationManager error:(NSError **)error;
@end

// Apple's factory supplies the nested secure-coding allowlists used by XPC
@protocol ParedServiceInterfaceAPI
+ (NSXPCInterface *)defaultInterface;
@end

@protocol ParedServiceAPI
// Subscriber names scope requests; they are not OS user identities
// Omit SubscriptionUser so the daemon resolves the XPC connection's effective
// UID, and send UserInitiated explicitly instead of relying on its default
- (oneway void)operationWithConfig:(NSDictionary *)configuration
                        completion:(void (^)(NSError *_Nullable))completion;
@end

// The synchronous status query also acquires and releases a MobileAsset lock
@protocol ParedAutoAssetManagerAPI
+ (id)latestStatusForClients:(NSString *)name error:(NSError **)error;
@end

// MAAutoAssetSetStatus reports signed 64-bit byte counts and boolean flags
@protocol ParedStatusAPI
- (NSString *_Nullable)latestDownloadedAtomicInstance;
- (NSArray *)configuredAssetEntries;
- (NSArray *)latestDowloadedAtomicInstanceEntries;
- (int64_t)downloadedNetworkBytes;
- (int64_t)downloadedFilesystemBytes;
- (BOOL)vendingAtomicInstanceForConfiguredEntries;
@end

// Downloaded entries are MAAutoAssetSetAtomicEntry; configured entries use a
// different class, so only inspect the downloaded array with these getters
@protocol ParedEntryAPI
- (NSString *)assetID;
- (id)fullAssetSelector;
@end

// Downloaded selectors identify the concrete asset type, specifier, and version
@protocol ParedSelectorAPI
- (NSString *)assetType;
- (NSString *)assetSpecifier;
- (NSString *)assetVersion;
@end

@interface ParedDownloadedAsset ()
- (instancetype)initWithAssetID:(NSString *)assetID
                      assetType:(NSString *)assetType
                 assetSpecifier:(NSString *)assetSpecifier
                   assetVersion:(NSString *)assetVersion
    NS_DESIGNATED_INITIALIZER;
@end
@implementation ParedDownloadedAsset
- (instancetype)initWithAssetID:(NSString *)assetID
                      assetType:(NSString *)assetType
                 assetSpecifier:(NSString *)assetSpecifier
                   assetVersion:(NSString *)assetVersion {
  if ((self = [super init])) {
    _assetID = [assetID copy];
    _assetType = [assetType copy];
    _assetSpecifier = [assetSpecifier copy];
    _assetVersion = [assetVersion copy];
  }
  return self;
}
@end

@interface ParedLocalDownloadStatus ()
- (instancetype)initWithAtomicInstance:(NSString *)atomicInstance
                  configuredEntryCount:(NSUInteger)configuredEntryCount
                      downloadedAssets:(NSArray<ParedDownloadedAsset *> *)assets
                          networkBytes:(int64_t)networkBytes
                       filesystemBytes:(int64_t)filesystemBytes
              vendingConfiguredEntries:(BOOL)vendingConfiguredEntries
    NS_DESIGNATED_INITIALIZER;
@end
@implementation ParedLocalDownloadStatus
- (instancetype)initWithAtomicInstance:(NSString *)atomicInstance
                  configuredEntryCount:(NSUInteger)configuredEntryCount
                      downloadedAssets:(NSArray<ParedDownloadedAsset *> *)assets
                          networkBytes:(int64_t)networkBytes
                       filesystemBytes:(int64_t)filesystemBytes
              vendingConfiguredEntries:(BOOL)vendingConfiguredEntries {
  if ((self = [super init])) {
    _latestDownloadedAtomicInstance = [atomicInstance copy];
    _downloadedAssets = [assets copy];
    _configuredAssetEntries = configuredEntryCount;
    _latestDowloadedAtomicInstanceEntries = assets.count;
    _downloadedNetworkBytes = networkBytes;
    _downloadedFilesystemBytes = filesystemBytes;
    _vendingAtomicInstanceForConfiguredEntries = vendingConfiguredEntries;
  }
  return self;
}
@end

@interface ParedAssetSubscription ()
@property(nonatomic, readonly, strong) id<ParedSubscriptionAPI> native;
- (instancetype)initWithNative:(id<ParedSubscriptionAPI>)native
    NS_DESIGNATED_INITIALIZER;
@end
@implementation ParedAssetSubscription
- (instancetype)initWithNative:(id<ParedSubscriptionAPI>)native {
  if ((self = [super init])) {
    _native = native;
  }
  return self;
}
@end

static void ParedSetError(NSError **error, NSString *message) {
  if (error) {
    *error = [NSError errorWithDomain:@"org.pared"
                                 code:69
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
}

// Compare semantic types, including oneway/block qualifiers, rather than stack
// offsets; offsets are architecture-specific and do not define the call
// contract
static BOOL ParedSignatureMatches(const char *actual, const char *expected) {
  if (!actual) {
    return NO;
  }
  NSMethodSignature *actualSignature =
      [NSMethodSignature signatureWithObjCTypes:actual];
  NSMethodSignature *expectedSignature =
      [NSMethodSignature signatureWithObjCTypes:expected];
  if (strcmp(actualSignature.methodReturnType,
             expectedSignature.methodReturnType) ||
      actualSignature.numberOfArguments !=
          expectedSignature.numberOfArguments) {
    return NO;
  }
  for (NSUInteger i = 0; i < actualSignature.numberOfArguments; i++) {
    if (strcmp([actualSignature getArgumentTypeAtIndex:i],
               [expectedSignature getArgumentTypeAtIndex:i])) {
      return NO;
    }
  }
  return YES;
}

static BOOL ParedHasMethod(id object, SEL selector, const char *encoding) {
  Method method = class_getInstanceMethod(object_getClass(object), selector);
  return method &&
         ParedSignatureMatches(method_getTypeEncoding(method), encoding);
}

static id<ParedConfigurationManagerAPI> ParedConfigurationManager(void) {
  Class type = NSClassFromString(@"UAFConfigurationManager");
  return ParedHasMethod(type, @selector(defaultManager), "@16@0:8")
             ? [(id<ParedConfigurationManagerAPI>)type defaultManager]
             : nil;
}

// Native validation checks set/usage names and alias/value pairs, but accepts
// empty scopes and arbitrary usage values; Pared requires ENABLED download
// usages and validates the scope separately
static BOOL ParedHasEnabledUsages(NSDictionary *sets) {
  for (id name in sets) {
    id usages = sets[name];
    if (![name isKindOfClass:NSString.class] ||
        ![usages isKindOfClass:NSDictionary.class] || [usages count] == 0) {
      return NO;
    }
    for (id usage in usages) {
      if (![usage isKindOfClass:NSString.class] ||
          ![usages[usage] isEqual:@"ENABLED"]) {
        return NO;
      }
    }
  }
  return YES;
}

// The native initializer stores strong references, including nested usage
// dictionaries; copy every string and dictionary before validation so caller
// mutations cannot change the scope later encoded for XPC
static NSDictionary<NSString *, NSString *> *
ParedCopyStringValues(NSDictionary *values) {
  if (![values isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  NSMutableDictionary<NSString *, NSString *> *snapshot =
      [NSMutableDictionary dictionary];
  for (id key in values) {
    id value = values[key];
    if (![key isKindOfClass:NSString.class] ||
        ![value isKindOfClass:NSString.class]) {
      return nil;
    }
    snapshot[key] = [value copy];
  }
  return [snapshot copy];
}

static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
ParedCopyAssetSetUsages(NSDictionary *sets) {
  if (![sets isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
      *snapshot = [NSMutableDictionary dictionary];
  for (id name in sets) {
    if (![name isKindOfClass:NSString.class]) {
      return nil;
    }
    NSDictionary *usages = ParedCopyStringValues(sets[name]);
    if (!usages) {
      return nil;
    }
    snapshot[name] = usages;
  }
  return [snapshot copy];
}

static id<ParedSubscriptionAPI>
ParedValidatedNativeSubscription(NSString *name, NSDictionary *assetSetUsages,
                                 NSDictionary *usageAliases, NSError **error) {
  Class type = NSClassFromString(@"UAFAssetSetSubscription");
  Method initializer = class_getInstanceMethod(
      type, @selector(initWithName:assetSets:usageAliases:));
  id<ParedConfigurationManagerAPI> manager = ParedConfigurationManager();
  if (!manager || !initializer ||
      !ParedSignatureMatches(method_getTypeEncoding(initializer),
                             "@40@0:8@16@24@32") ||
      !ParedHasMethod(type, @selector(supportsSecureCoding), "B16@0:8") ||
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
      !ParedHasMethod(native, @selector(isValid:error:), "B32@0:8@16^@24")) {
    ParedSetError(error,
                  @"Required subscription validation interface is unavailable");
    return nil;
  }
  // Validate before any unsubscribe so a rejected replacement leaves existing
  // subscriptions intact; this checks configuration, not download completion
  NSError *validationError = nil;
  if (![native isValid:manager error:&validationError] || validationError) {
    if (error) {
      *error = validationError;
    }
    if (!validationError) {
      ParedSetError(error, @"Apple rejected the download subscription");
    }
    return nil;
  }
  return native;
}

ParedAssetSubscription *ParedSubscription(NSString *name,
                                          NSDictionary *assetSetUsages,
                                          NSDictionary *usageAliases,
                                          NSError **error) {
  name = [name copy];
  assetSetUsages = ParedCopyAssetSetUsages(assetSetUsages);
  usageAliases = ParedCopyStringValues(usageAliases);
  if (!assetSetUsages || !usageAliases || name.length == 0 ||
      (assetSetUsages.count == 0 && usageAliases.count == 0) ||
      !ParedHasEnabledUsages(assetSetUsages)) {
    ParedSetError(error,
                  @"A download subscription requires a name and nonempty "
                  @"ENABLED usages or aliases");
    return nil;
  }
  id<ParedSubscriptionAPI> native = ParedValidatedNativeSubscription(
      name, assetSetUsages, usageAliases, error);
  if (!native) {
    return nil;
  }
  for (NSString *alias in usageAliases) {
    NSDictionary *resolved = ParedResolveUsageAlias(alias, usageAliases[alias]);
    if (resolved.count == 0 || !ParedHasEnabledUsages(resolved)) {
      ParedSetError(
          error, @"Download alias did not resolve to nonempty ENABLED usages");
      return nil;
    }
  }
  return [[ParedAssetSubscription alloc] initWithNative:native];
}

// Only downloaded entries use this selector contract; configured entries are
// counted without assuming that they have the same private class
static ParedDownloadedAsset *ParedCopyDownloadedAsset(id<ParedEntryAPI> entry,
                                                      NSError **error) {
  if (!ParedHasMethod(entry, @selector(assetID), "@16@0:8") ||
      !ParedHasMethod(entry, @selector(fullAssetSelector), "@16@0:8")) {
    ParedSetError(error, @"Unknown downloaded asset entry interface");
    return nil;
  }
  id<ParedSelectorAPI> selector = [entry fullAssetSelector];
  if (!ParedHasMethod(selector, @selector(assetType), "@16@0:8") ||
      !ParedHasMethod(selector, @selector(assetSpecifier), "@16@0:8") ||
      !ParedHasMethod(selector, @selector(assetVersion), "@16@0:8")) {
    ParedSetError(error, @"Unknown downloaded asset selector interface");
    return nil;
  }
  id assetID = [entry assetID];
  id assetType = [selector assetType];
  id specifier = [selector assetSpecifier];
  id version = [selector assetVersion];
  if (![assetID isKindOfClass:NSString.class] ||
      ![assetType isKindOfClass:NSString.class] ||
      ![specifier isKindOfClass:NSString.class] ||
      ![version isKindOfClass:NSString.class]) {
    ParedSetError(error, @"Unknown downloaded asset value types");
    return nil;
  }
  return [[ParedDownloadedAsset alloc] initWithAssetID:assetID
                                             assetType:assetType
                                        assetSpecifier:specifier
                                          assetVersion:version];
}

// The status query briefly locks the latest atomic instance, then releases it
// before returning; lock-release errors can accompany a usable snapshot
// Byte counts can be zero even with assets present
// These counts describe a snapshot, not live progress or reclaimable APFS space
// MobileAsset NoSharedLock 6582 can mean a missing latest-instance lock
// symlink; preserve that error rather than manufacturing a snapshot with zero
// assets
ParedLocalDownloadStatus *ParedLocalStatus(NSString *assetSet,
                                           NSError **error) {
  Class type = NSClassFromString(@"UAFAutoAssetManager");
  if (!ParedHasMethod(type, @selector(latestStatusForClients:error:),
                      "@32@0:8@16^@24")) {
    ParedSetError(error, @"Local asset status interface is unavailable");
    return nil;
  }
  NSError *statusError = nil;
  id<ParedStatusAPI> status =
      [(id<ParedAutoAssetManagerAPI>)type latestStatusForClients:assetSet
                                                           error:&statusError];
  if (statusError) {
    if (error) {
      *error = statusError;
    }
    return nil;
  }
  if (!status) {
    return nil;
  }
  SEL objectGetters[] = {@selector(latestDownloadedAtomicInstance),
                         @selector(configuredAssetEntries),
                         @selector(latestDowloadedAtomicInstanceEntries)};
  for (size_t i = 0; i < sizeof(objectGetters) / sizeof(objectGetters[0]);
       i++) {
    if (!ParedHasMethod(status, objectGetters[i], "@16@0:8")) {
      ParedSetError(error, @"Unknown asset status object interface");
      return nil;
    }
  }
  if (!ParedHasMethod(status, @selector(downloadedNetworkBytes), "q16@0:8") ||
      !ParedHasMethod(status, @selector(downloadedFilesystemBytes),
                      "q16@0:8") ||
      !ParedHasMethod(status,
                      @selector(vendingAtomicInstanceForConfiguredEntries),
                      "B16@0:8")) {
    ParedSetError(error, @"Unknown asset status scalar interface");
    return nil;
  }
  id instance = [status latestDownloadedAtomicInstance];
  id configured = [status configuredAssetEntries];
  id downloaded = [status latestDowloadedAtomicInstanceEntries];
  if ((instance && ![instance isKindOfClass:NSString.class]) ||
      ![configured isKindOfClass:NSArray.class] ||
      ![downloaded isKindOfClass:NSArray.class]) {
    ParedSetError(error, @"Unknown asset status value types");
    return nil;
  }
  NSMutableArray<ParedDownloadedAsset *> *assets = [NSMutableArray array];
  for (id entry in downloaded) {
    ParedDownloadedAsset *asset = ParedCopyDownloadedAsset(entry, error);
    if (!asset) {
      return nil;
    }
    [assets addObject:asset];
  }
  // Pass validated values into the wrapper rather than querying private getters
  // a second time while initializing the immutable snapshot
  return [[ParedLocalDownloadStatus alloc]
        initWithAtomicInstance:instance
          configuredEntryCount:[configured count]
              downloadedAssets:assets
                  networkBytes:[status downloadedNetworkBytes]
               filesystemBytes:[status downloadedFilesystemBytes]
      vendingConfiguredEntries:[status
                                   vendingAtomicInstanceForConfiguredEntries]];
}

NSXPCInterface *ParedServiceInterface(void) {
  Class type = NSClassFromString(@"UAFXPCProxyServiceInterface");
  if (!ParedHasMethod(type, @selector(defaultInterface), "@16@0:8")) {
    return nil;
  }
  id value = [(id<ParedServiceInterfaceAPI>)type defaultInterface];
  if (![value isKindOfClass:NSXPCInterface.class]) {
    return nil;
  }
  NSXPCInterface *interface = value;
  SEL operation = @selector(operationWithConfig:completion:);
  struct objc_method_description method =
      protocol_getMethodDescription(interface.protocol, operation, YES, YES);
  if (!ParedSignatureMatches(method.types, "Vv32@0:8@16@?24")) {
    return nil;
  }
  // Vv is oneway void; @? is a block, not an ordinary object argument
  // Preserve Apple's interface; its nested subscription allowlist is part of
  // the wire contract and cannot be inferred from a Swift protocol's signature
  NSSet *request = [interface classesForSelector:operation
                                   argumentIndex:0
                                         ofReply:NO];
  Class subscription = NSClassFromString(@"UAFAssetSetSubscription");
  if (!subscription || ![request containsObject:subscription] ||
      ![request containsObject:NSString.class] ||
      ![request containsObject:NSDictionary.class] ||
      ![request containsObject:NSArray.class] ||
      ![request containsObject:NSNumber.class] ||
      ![[interface classesForSelector:operation argumentIndex:0
                              ofReply:YES] containsObject:NSError.class]) {
    return nil;
  }
  return interface;
}

static BOOL ParedHasNonemptyStrings(NSArray *values) {
  if (![values isKindOfClass:NSArray.class]) {
    return NO;
  }
  for (id value in values) {
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
      return NO;
    }
  }
  return YES;
}

BOOL ParedPerformReset(NSObject *proxy, NSArray<NSString *> *assetSets,
                       void (^completion)(NSError *_Nullable),
                       NSError **error) {
  // A missing AssetSets field means every set to the daemon; reject empty input
  // Reset aggregates per-set errors and continues with other selected sets
  // Its fallback may force elimination without waiting for existing locks
  // An initial removal error remains in the reply even if the fallback succeeds
  // Asset-type elimination errors are only logged, so nil is not proof that
  // every payload was deleted
  if (!ParedHasNonemptyStrings(assetSets) || assetSets.count == 0) {
    ParedSetError(
        error,
        @"Reset requires explicit nonempty asset set names; no request sent");
    return NO;
  }
  NSDictionary *configuration =
      @{@"Operation" : @"ResetAssetSets", @"AssetSets" : assetSets};
  [(id<ParedServiceAPI>)proxy operationWithConfig:configuration
                                       completion:completion];
  return YES;
}

BOOL ParedPerformSubscribe(NSObject *proxy, NSString *subscriber,
                           NSArray<ParedAssetSubscription *> *subscriptions,
                           void (^completion)(NSError *_Nullable),
                           NSError **error) {
  if (subscriber.length == 0 || subscriptions.count == 0) {
    ParedSetError(error, @"Subscribe requires a subscriber and validated "
                         @"subscriptions; no request sent");
    return NO;
  }
  NSMutableArray *native =
      [NSMutableArray arrayWithCapacity:subscriptions.count];
  for (ParedAssetSubscription *subscription in subscriptions) {
    if (![subscription isKindOfClass:ParedAssetSubscription.class] ||
        !subscription.native) {
      ParedSetError(error, @"Unknown subscription wrapper; no request sent");
      return NO;
    }
    [native addObject:subscription.native];
  }
  NSDictionary *configuration = @{
    @"Operation" : @"Subscribe",
    @"Subscriber" : subscriber,
    @"Subscriptions" : native,
    @"UserInitiated" : @YES
  };
  [(id<ParedServiceAPI>)proxy operationWithConfig:configuration
                                       completion:completion];
  return YES;
}

BOOL ParedPerformUnsubscribe(NSObject *proxy, NSString *subscriber,
                             NSArray<NSString *> *names,
                             void (^completion)(NSError *_Nullable),
                             NSError **error) {
  if (subscriber.length == 0 || !ParedHasNonemptyStrings(names) ||
      names.count == 0) {
    ParedSetError(error, @"Unsubscribe requires a subscriber and subscription "
                         @"names; no request sent");
    return NO;
  }
  NSArray<NSString *> *unique = [[[NSSet setWithArray:names] allObjects]
      sortedArrayUsingSelector:@selector(compare:)];
  NSDictionary *configuration = @{
    @"Operation" : @"Unsubscribe",
    @"Subscriber" : subscriber,
    @"Subscriptions" : unique,
    @"UserInitiated" : @YES
  };
  [(id<ParedServiceAPI>)proxy operationWithConfig:configuration
                                       completion:completion];
  return YES;
}

static id<ParedAssetSetAPI> ParedAssetSet(NSString *name) {
  id<ParedConfigurationManagerAPI> manager = ParedConfigurationManager();
  return ParedHasMethod(manager, @selector(getAssetSet:), "@24@0:8@16")
             ? [manager getAssetSet:name]
             : nil;
}

NSString *ParedAssetTypeForSet(NSString *name) {
  id<ParedAssetSetAPI> set = ParedAssetSet(name);
  if (!ParedHasMethod(set, @selector(autoAssetType), "@16@0:8")) {
    return nil;
  }
  id value = [set autoAssetType];
  return [value isKindOfClass:NSString.class] ? [value copy] : nil;
}

NSArray<NSString *> *ParedUsageTypesForSet(NSString *name) {
  id<ParedAssetSetAPI> set = ParedAssetSet(name);
  if (!ParedHasMethod(set, @selector(usageTypes), "@16@0:8")) {
    return nil;
  }
  id value = [set usageTypes];
  if (!ParedHasNonemptyStrings(value)) {
    return nil;
  }
  NSMutableArray<NSString *> *names =
      [NSMutableArray arrayWithCapacity:[value count]];
  for (NSString *usage in value) {
    [names addObject:[usage copy]];
  }
  return [names copy];
}

NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
ParedResolveUsageAlias(NSString *alias, NSString *value) {
  // An alias can expand across asset sets, including download dependencies
  // such as Overrides and Shortcuts.Generator; callers must check the expansion
  // against their declared sets before subscribing
  id<ParedConfigurationManagerAPI> manager = ParedConfigurationManager();
  if (!ParedHasMethod(
          manager, @selector(getAssetSetUsagesForUsageAlias:usageAliasValue:),
          "@32@0:8@16@24")) {
    return nil;
  }
  id result = [manager getAssetSetUsagesForUsageAlias:alias
                                      usageAliasValue:value];
  // Apple returns the configured value dictionary directly, including fallback
  // values for deprecated aliases; keep private configuration containers local
  return ParedCopyAssetSetUsages(result);
}
