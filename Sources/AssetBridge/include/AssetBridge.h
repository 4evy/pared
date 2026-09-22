#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Use Objective-C's native initializer ABI and ARC for this private object
FOUNDATION_EXPORT NSObject *_Nullable ParedSubscription(
    NSString *name,
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
        *assetSetUsages,
    NSDictionary<NSString *, NSString *> *usageAliases);
FOUNDATION_EXPORT
NSDictionary<NSString *, id> *_Nullable ParedLocalStatus(NSString *assetSet,
                                                         NSError **error);
// Objective-C encoding: Vv32@0:8@16@?24 (oneway void, dictionary, block).
FOUNDATION_EXPORT void
ParedPerformOperation(NSObject *proxy,
                      NSDictionary<NSString *, id> *configuration,
                      void (^completion)(NSError *_Nullable error));
FOUNDATION_EXPORT NSXPCInterface *_Nullable ParedServiceInterface(void);
FOUNDATION_EXPORT NSString *_Nullable ParedAssetTypeForSet(NSString *assetSet);
FOUNDATION_EXPORT
NSArray<NSString *> *_Nullable ParedUsageTypesForSet(NSString *assetSet);
FOUNDATION_EXPORT
NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *>
    *_Nullable ParedResolveUsageAlias(NSString *alias, NSString *value);
NS_ASSUME_NONNULL_END
