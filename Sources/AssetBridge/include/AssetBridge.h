#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Copied identifiers for a downloaded asset
@interface ParedDownloadedAsset : NSObject
@property(nonatomic, readonly, copy) NSString *assetID;
@property(nonatomic, readonly, copy) NSString *assetType;
@property(nonatomic, readonly, copy) NSString *assetSpecifier;
@property(nonatomic, readonly, copy) NSString *assetVersion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// A local snapshot; its byte counts do not measure reclaimable disk space
@interface ParedLocalDownloadStatus : NSObject
@property(nonatomic, readonly, copy, nullable)
    NSString *latestDownloadedAtomicInstance;
@property(nonatomic, readonly, copy)
    NSArray<ParedDownloadedAsset *> *downloadedAssets;
@property(nonatomic, readonly) NSUInteger configuredAssetEntries;
// Keep Apple's spelling for compatibility with existing output
@property(nonatomic, readonly) NSUInteger latestDowloadedAtomicInstanceEntries;
@property(nonatomic, readonly) int64_t downloadedNetworkBytes;
@property(nonatomic, readonly) int64_t downloadedFilesystemBytes;
@property(nonatomic, readonly) BOOL vendingAtomicInstanceForConfiguredEntries;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// A validated subscription ready to send through XPC
@interface ParedAssetSubscription : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Creates a subscription using the current configuration
///
/// Requires a nonempty name and ENABLED usages or aliases. Copies caller inputs
/// and checks the native object kept those values without an expiration
///
/// Unsubscribe explicitly to remove the request. The daemon resolves aliases
/// again when processing it
FOUNDATION_EXPORT ParedAssetSubscription *_Nullable ParedSubscription(
    NSString *name,
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
        *assetSetUsages,
    NSDictionary<NSString *, NSString *> *usageAliases,
    NSError *_Nullable *_Nullable error);
/// Returns a copied status, or nil with an error if the query or validation
/// fails A lock-release error also fails the query, even if Apple returned
/// status
///
/// The result holds no lock and does not keep asset files available
FOUNDATION_EXPORT ParedLocalDownloadStatus *_Nullable ParedLocalStatus(
    NSString *assetSet, NSError *_Nullable *_Nullable error);

/// Resets the named asset sets for all users, leaving subscriptions intact
/// Use a proxy from a connection configured with ParedServiceInterface
///
/// Returns NO with an error without sending or calling completion if the
/// request is invalid. YES means it was handed to the proxy; completion runs on
/// the connection's reply queue
///
/// A successful reply does not prove every payload was deleted. A timeout or
/// transport error can follow daemon effects; check the outcome before retrying
FOUNDATION_EXPORT BOOL
ParedPerformReset(NSObject *proxy, NSArray<NSString *> *assetSets,
                  void (^completion)(NSError *_Nullable error),
                  NSError *_Nullable *_Nullable error);
/// Subscribes validated requests; duplicate names are rejected
///
/// A successful reply does not promise a download. Identical subscriptions and
/// unchanged demand across subscribers may skip asset configuration, and some
/// download errors are only logged
///
/// Configuration changes can survive a failed database write
/// Uses the proxy, return value, and completion behavior of ParedPerformReset
FOUNDATION_EXPORT BOOL
ParedPerformSubscribe(NSObject *proxy, NSString *subscriber,
                      NSArray<ParedAssetSubscription *> *subscriptions,
                      void (^completion)(NSError *_Nullable error),
                      NSError *_Nullable *_Nullable error);
/// Removes named requests for a subscriber, including already absent names
/// Other subscribers can keep the same assets requested. Unreadable stored
/// requests may be skipped as though absent
///
/// Uses the proxy, return value, and completion behavior of ParedPerformReset
FOUNDATION_EXPORT BOOL ParedPerformUnsubscribe(
    NSObject *proxy, NSString *subscriber, NSArray<NSString *> *names,
    void (^completion)(NSError *_Nullable error),
    NSError *_Nullable *_Nullable error);
/// Returns Apple's XPC interface, or nil if its signatures or allowed classes
/// are incompatible
FOUNDATION_EXPORT NSXPCInterface *_Nullable ParedServiceInterface(void);
/// Returns a copied asset type, or nil if unavailable
FOUNDATION_EXPORT NSString *_Nullable ParedAssetTypeForSet(NSString *assetSet);
/// Returns copied usage names, or nil if unavailable
FOUNDATION_EXPORT
NSArray<NSString *> *_Nullable ParedUsageTypesForSet(NSString *assetSet);
/// Returns a copied alias expansion, or nil if unavailable
/// Expansions may include dependencies in other asset sets and deprecated
/// values
FOUNDATION_EXPORT
NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
    *_Nullable ParedResolveUsageAlias(NSString *alias, NSString *value);
NS_ASSUME_NONNULL_END
