#import "BridgeInternal.h"

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
- (instancetype)initWithAtomicInstance:(NSString *_Nullable)atomicInstance
                  configuredEntryCount:(NSUInteger)configuredEntryCount
                      downloadedAssets:(NSArray<ParedDownloadedAsset *> *)assets
                          networkBytes:(int64_t)networkBytes
                       filesystemBytes:(int64_t)filesystemBytes
              vendingConfiguredEntries:(BOOL)vendingConfiguredEntries
    NS_DESIGNATED_INITIALIZER;
@end
@implementation ParedLocalDownloadStatus
- (instancetype)initWithAtomicInstance:(NSString *_Nullable)atomicInstance
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

// Check getter signatures before calling them; the same selector could return
// an object, an integer, or a boolean
static BOOL ParedHasStatusInterface(id<ParedAssetSetStatusAPI> status,
                                    NSError **error) {
  if (!ParedHasDeclaredMethods(status,
                               @protocol(ParedAssetSetStatusObjectsAPI))) {
    ParedSetError(error, @"Unknown asset status object interface");
    return NO;
  }
  if (!ParedHasDeclaredMethods(status,
                               @protocol(ParedAssetSetStatusScalarsAPI))) {
    ParedSetError(error, @"Unknown asset status scalar interface");
    return NO;
  }
  return YES;
}

// Configured entries have a different class; only use these getters on
// downloaded entries
static ParedDownloadedAsset *
ParedCopyDownloadedAsset(id<ParedDownloadedEntryAPI> entry, NSError **error) {
  if (!ParedHasDeclaredMethods(entry, @protocol(ParedDownloadedEntryAPI))) {
    ParedSetError(error, @"Unknown downloaded asset entry interface");
    return nil;
  }
  id<ParedAutoAssetSelectorAPI> selector = [entry fullAssetSelector];
  if (!ParedHasDeclaredMethods(selector,
                               @protocol(ParedAutoAssetSelectorAPI))) {
    ParedSetError(error, @"Unknown downloaded asset selector interface");
    return nil;
  }
  id assetID = [entry assetID];
  id assetType = [selector assetType];
  id specifier = [selector assetSpecifier];
  id version = [selector assetVersion];
  if (!ParedNonemptyString(assetID) || !ParedNonemptyString(assetType) ||
      !ParedNonemptyString(specifier) || !ParedNonemptyString(version)) {
    ParedSetError(error, @"Unknown downloaded asset value types");
    return nil;
  }
  return [[ParedDownloadedAsset alloc] initWithAssetID:assetID
                                             assetType:assetType
                                        assetSpecifier:specifier
                                          assetVersion:version];
}

// The query validates downloaded content while holding a shared lock, then
// releases it before returning. Report query and release errors even if Apple
// also supplies a status object
//
// The copied snapshot holds no lock, so files can disappear afterward. Byte
// counts can be zero with assets present and do not measure reclaimable space
ParedLocalDownloadStatus *ParedLocalStatus(NSString *assetSet,
                                           NSError **error) {
  if (!ParedNonemptyString(assetSet)) {
    ParedSetError(error, @"Local status requires a nonempty asset set name");
    return nil;
  }
  Class type = NSClassFromString(@"UAFAutoAssetManager");
  if (!ParedHasMethod(type, @selector(latestStatusForClients:error:),
                      @protocol(ParedAutoAssetManagerAPI))) {
    ParedSetError(error, @"Local asset status interface is unavailable");
    return nil;
  }
  NSError *statusError = nil;
  id<ParedAssetSetStatusAPI> status =
      [(id<ParedAutoAssetManagerAPI>)type latestStatusForClients:assetSet
                                                           error:&statusError];
  if (statusError) {
    ParedSetReturnedError(error, statusError);
    return nil;
  }
  if (!status) {
    ParedSetError(error, @"Apple returned no local asset status");
    return nil;
  }
  if (!ParedHasStatusInterface(status, error)) {
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
  Class configuredEntryType = NSClassFromString(@"MAAutoAssetSetEntry");
  for (id entry in configured) {
    if (!configuredEntryType || ![entry isKindOfClass:configuredEntryType]) {
      ParedSetError(error, @"Unknown configured asset entry class");
      return nil;
    }
  }
  NSMutableArray<ParedDownloadedAsset *> *assets = [NSMutableArray array];
  for (id entry in downloaded) {
    ParedDownloadedAsset *asset = ParedCopyDownloadedAsset(entry, error);
    if (!asset) {
      return nil;
    }
    [assets addObject:asset];
  }
  // Use the values already checked above; do not read private getters again
  // while building the snapshot
  int64_t networkBytes = [status downloadedNetworkBytes];
  int64_t filesystemBytes = [status downloadedFilesystemBytes];
  BOOL vendingConfiguredEntries =
      [status vendingAtomicInstanceForConfiguredEntries];
  return [[ParedLocalDownloadStatus alloc]
        initWithAtomicInstance:instance
          configuredEntryCount:[configured count]
              downloadedAssets:assets
                  networkBytes:networkBytes
               filesystemBytes:filesystemBytes
      vendingConfiguredEntries:vendingConfiguredEntries];
}
