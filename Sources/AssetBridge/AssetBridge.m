#import "AssetBridge.h"

@interface NSObject (ParedSubscription)
+ (id)defaultManager;
+ (NSXPCInterface *)defaultInterface;
- (id)getAssetSet:(NSString *)name;
- (NSString *)autoAssetType;
- (NSArray<NSString *> *)usageTypes;
- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)
    getAssetSetUsagesForUsageAlias:(NSString *)alias
                   usageAliasValue:(NSString *)value;
- (instancetype)initWithName:(NSString *)name
                   assetSets:(NSDictionary *)sets
                usageAliases:(NSDictionary *)aliases;
- (oneway void)operationWithConfig:(NSDictionary *)configuration
                        completion:(void (^)(NSError *_Nullable))completion;
- (NSString *)latestDownloadedAtomicInstance;
- (NSArray *)configuredAssetEntries;
- (NSArray *)latestDowloadedAtomicInstanceEntries;
- (int64_t)downloadedNetworkBytes;
- (int64_t)downloadedFilesystemBytes;
- (BOOL)vendingAtomicInstanceForConfiguredEntries;
- (NSString *)assetID;
- (NSObject *)fullAssetSelector;
- (NSString *)assetType;
- (NSString *)assetSpecifier;
- (NSString *)assetVersion;
+ (id)latestStatusForClients:(NSString *)name error:(NSError **)error;
@end

NSObject *ParedSubscription(NSString *name, NSDictionary *assetSetUsages,
                            NSDictionary *usageAliases) {
  Class type = NSClassFromString(@"UAFAssetSetSubscription");
  if (![type instancesRespondToSelector:
                 @selector(initWithName:assetSets:usageAliases:)]) {
    return nil;
  }
  return [[type alloc] initWithName:name
                          assetSets:assetSetUsages
                       usageAliases:usageAliases];
}

// Snapshot bytes are not reclaimed APFS space or live download progress. After
// cleanup, NoSharedLock 6582 can mean the latest-instance lock is gone, not
// zero assets
NSDictionary *ParedLocalStatus(NSString *assetSet, NSError **error) {
  Class type = NSClassFromString(@"UAFAutoAssetManager");
  if (![type respondsToSelector:@selector(latestStatusForClients:error:)]) {
    if (error)
      *error =
          [NSError errorWithDomain:@"org.pared"
                              code:69
                          userInfo:@{
                            NSLocalizedDescriptionKey :
                                @"Local asset status interface is unavailable"
                          }];
    return nil;
  }
  NSObject *status = [type latestStatusForClients:assetSet error:error];
  if (!status)
    return nil;
  // MAAutoAssetSetStatus properties: NSString, NSArray, NSArray, q, q, B.
  // Keep Apple's misspelling of latestDowloadedAtomicInstanceEntries.
  SEL required[] = {@selector(latestDownloadedAtomicInstance),
                    @selector(configuredAssetEntries),
                    @selector(latestDowloadedAtomicInstanceEntries),
                    @selector(downloadedNetworkBytes),
                    @selector(downloadedFilesystemBytes),
                    @selector(vendingAtomicInstanceForConfiguredEntries)};
  for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
    if (![status respondsToSelector:required[i]]) {
      if (error)
        *error = [NSError errorWithDomain:@"org.pared"
                                     code:69
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"Unknown asset status interface"
                                 }];
      return nil;
    }
  }
  NSString *instance = [status latestDownloadedAtomicInstance];
  NSArray *configured = [status configuredAssetEntries];
  NSArray *downloaded = [status latestDowloadedAtomicInstanceEntries];
  BOOL valid = (!instance || [instance isKindOfClass:NSString.class]) &&
               [configured isKindOfClass:NSArray.class] &&
               [downloaded isKindOfClass:NSArray.class];
  NSMutableArray *assets = [NSMutableArray array];
  if (valid)
    for (NSObject *entry in downloaded) {
      if (![entry respondsToSelector:@selector(assetID)] ||
          ![entry respondsToSelector:@selector(fullAssetSelector)]) {
        valid = NO;
        break;
      }
      NSObject *selector = [entry fullAssetSelector];
      if (![selector respondsToSelector:@selector(assetType)] ||
          ![selector respondsToSelector:@selector(assetSpecifier)] ||
          ![selector respondsToSelector:@selector(assetVersion)]) {
        valid = NO;
        break;
      }
      NSString *assetID = [entry assetID];
      NSString *assetType = [selector assetType];
      NSString *assetSpecifier = [selector assetSpecifier];
      NSString *assetVersion = [selector assetVersion];
      if (![assetID isKindOfClass:NSString.class] ||
          ![assetType isKindOfClass:NSString.class] ||
          ![assetSpecifier isKindOfClass:NSString.class] ||
          ![assetVersion isKindOfClass:NSString.class]) {
        valid = NO;
        break;
      }
      [assets addObject:@{
        @"assetID" : assetID,
        @"assetType" : assetType,
        @"assetSpecifier" : assetSpecifier,
        @"assetVersion" : assetVersion
      }];
    }
  if (!valid) {
    if (error)
      *error = [NSError errorWithDomain:@"org.pared"
                                   code:69
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Unknown asset status value types"
                               }];
    return nil;
  }
  return @{
    @"latestDownloadedAtomicInstance" : instance ?: NSNull.null,
    @"configuredAssetEntries" : @(configured.count),
    @"latestDowloadedAtomicInstanceEntries" : @(downloaded.count),
    @"downloadedNetworkBytes" : @([status downloadedNetworkBytes]),
    @"downloadedFilesystemBytes" : @([status downloadedFilesystemBytes]),
    @"vendingAtomicInstanceForConfiguredEntries" :
        @([status vendingAtomicInstanceForConfiguredEntries]),
    @"downloadedAssets" : assets
  };
}

void ParedPerformOperation(NSObject *proxy,
                           NSDictionary<NSString *, id> *configuration,
                           void (^completion)(NSError *_Nullable)) {
  [proxy operationWithConfig:configuration completion:completion];
}

NSXPCInterface *ParedServiceInterface(void) {
  Class type = NSClassFromString(@"UAFXPCProxyServiceInterface");
  if (![type respondsToSelector:@selector(defaultInterface)])
    return nil;
  id value = [type defaultInterface];
  return [value isKindOfClass:NSXPCInterface.class] ? value : nil;
}

static id ParedConfigurationManager(void) {
  Class type = NSClassFromString(@"UAFConfigurationManager");
  return [type respondsToSelector:@selector(defaultManager)]
             ? [type defaultManager]
             : nil;
}

static id ParedAssetSet(NSString *name) {
  id manager = ParedConfigurationManager();
  return [manager respondsToSelector:@selector(getAssetSet:)]
             ? [manager getAssetSet:name]
             : nil;
}

NSString *ParedAssetTypeForSet(NSString *name) {
  id set = ParedAssetSet(name);
  if (![set respondsToSelector:@selector(autoAssetType)])
    return nil;
  id value = [set autoAssetType];
  return [value isKindOfClass:NSString.class] ? value : nil;
}

NSArray<NSString *> *ParedUsageTypesForSet(NSString *name) {
  id set = ParedAssetSet(name);
  if (![set respondsToSelector:@selector(usageTypes)])
    return nil;
  id value = [set usageTypes];
  if (![value isKindOfClass:NSArray.class])
    return nil;
  for (id item in value)
    if (![item isKindOfClass:NSString.class])
      return nil;
  return value;
}

NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *
ParedResolveUsageAlias(NSString *alias, NSString *value) {
  id manager = ParedConfigurationManager();
  if (![manager respondsToSelector:
                    @selector(getAssetSetUsagesForUsageAlias:usageAliasValue:)])
    return nil;
  id result = [manager getAssetSetUsagesForUsageAlias:alias
                                      usageAliasValue:value];
  if (![result isKindOfClass:NSDictionary.class])
    return nil;
  for (id set in result) {
    if (![set isKindOfClass:NSString.class])
      return nil;
    id usages = result[set];
    if (![usages isKindOfClass:NSDictionary.class])
      return nil;
    for (id usage in usages) {
      if (![usage isKindOfClass:NSString.class] ||
          ![usages[usage] isKindOfClass:NSString.class])
        return nil;
    }
  }
  return result;
}
