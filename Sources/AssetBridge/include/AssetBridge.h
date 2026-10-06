#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable, validated copies of downloaded asset values
@interface ParedDownloadedAsset : NSObject
@property(nonatomic, readonly, copy) NSString *assetID;
@property(nonatomic, readonly, copy) NSString *assetType;
@property(nonatomic, readonly, copy) NSString *assetSpecifier;
@property(nonatomic, readonly, copy) NSString *assetVersion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// A local snapshot whose byte counts do not measure reclaimable disk space
@interface ParedLocalDownloadStatus : NSObject
@property(nonatomic, readonly, copy, nullable)
    NSString *latestDownloadedAtomicInstance;
@property(nonatomic, readonly, copy)
    NSArray<ParedDownloadedAsset *> *downloadedAssets;
@property(nonatomic, readonly) NSUInteger configuredAssetEntries;
// Preserve Apple's misspelled selector in the existing output schema
@property(nonatomic, readonly) NSUInteger latestDowloadedAtomicInstanceEntries;
@property(nonatomic, readonly) int64_t downloadedNetworkBytes;
@property(nonatomic, readonly) int64_t downloadedFilesystemBytes;
@property(nonatomic, readonly) BOOL vendingAtomicInstanceForConfiguredEntries;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Owns a validated native subscription for transport through Apple's XPC
/// interface
@interface ParedAssetSubscription : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Constructs a subscription validated against live configuration
/// Accepts only nonempty scopes with ENABLED usage values and snapshots caller
/// strings and nested dictionaries before validation
/// Requests no expiration; unsubscribe explicitly to remove the request
FOUNDATION_EXPORT ParedAssetSubscription *_Nullable ParedSubscription(
    NSString *name,
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
        *assetSetUsages,
    NSDictionary<NSString *, NSString *> *usageAliases,
    NSError *_Nullable *_Nullable error);
/// Returns nil for query or lock-release errors, even when Apple returns status
FOUNDATION_EXPORT ParedLocalDownloadStatus *_Nullable ParedLocalStatus(
    NSString *assetSet, NSError *_Nullable *_Nullable error);

/// Sends a reset for explicit nonempty asset set names
/// Returns NO without sending if the bridge cannot construct a supported
/// request The proxy must come from a connection configured with
/// ParedServiceInterface Completion runs on the connection's reply queue;
/// success does not guarantee that every payload was deleted
FOUNDATION_EXPORT BOOL
ParedPerformReset(NSObject *proxy, NSArray<NSString *> *assetSets,
                  void (^completion)(NSError *_Nullable error),
                  NSError *_Nullable *_Nullable error);
/// Sends validated subscriptions and acknowledges configuration, not downloads
/// Apple compares names, explicit usages, aliases, and expiration; unchanged
/// subscriptions succeed without triggering a new configuration
/// Uses the same proxy and completion queue contract as ParedPerformReset
FOUNDATION_EXPORT BOOL
ParedPerformSubscribe(NSObject *proxy, NSString *subscriber,
                      NSArray<ParedAssetSubscription *> *subscriptions,
                      void (^completion)(NSError *_Nullable error),
                      NSError *_Nullable *_Nullable error);
/// Removes subscription names for a subscriber, including already absent names
/// The reply does not prove assets were deleted; other subscribers can continue
/// requesting the same assets
/// Uses the same proxy and completion queue contract as ParedPerformReset
FOUNDATION_EXPORT BOOL ParedPerformUnsubscribe(
    NSObject *proxy, NSString *subscriber, NSArray<NSString *> *names,
    void (^completion)(NSError *_Nullable error),
    NSError *_Nullable *_Nullable error);
/// Returns Apple's interface only when its signature and allowlists are
/// supported
FOUNDATION_EXPORT NSXPCInterface *_Nullable ParedServiceInterface(void);
/// Returns a copied asset type from live configuration, or nil if unavailable
FOUNDATION_EXPORT NSString *_Nullable ParedAssetTypeForSet(NSString *assetSet);
/// Returns copied usage names from live configuration, or nil if unavailable
FOUNDATION_EXPORT
NSArray<NSString *> *_Nullable ParedUsageTypesForSet(NSString *assetSet);
/// Returns a deep immutable copy of an alias expansion, or nil if unavailable
/// Apple can resolve deprecated alias values; expansions may include
/// dependencies
FOUNDATION_EXPORT
NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
    *_Nullable ParedResolveUsageAlias(NSString *alias, NSString *value);
NS_ASSUME_NONNULL_END
