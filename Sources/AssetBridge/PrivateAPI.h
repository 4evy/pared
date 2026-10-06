#pragma once

#import <Foundation/Foundation.h>

// These protocols describe the private methods we call; Apple's classes do not
// conform to them. Check method signatures before casting and check returned
// objects before using them, since Objective-C erases their class and generics

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, NSString *> ParedStringValues;
typedef NSDictionary<NSString *, ParedStringValues *> ParedAssetSetUsages;

@protocol ParedAssetSetConfigurationAPI;
@protocol ParedAssetSetStatusAPI;
@protocol ParedDownloadedEntryAPI;
@protocol ParedAutoAssetSelectorAPI;
@class MAAutoAssetSetEntry;

// The shared manager caches asset set configurations and returns nil when it
// cannot load one. Alias lookup falls back to deprecated values and returns
// its configuration dictionaries directly, so callers need to copy them
@protocol ParedConfigurationManagerAPI <NSObject>
+ (id<ParedConfigurationManagerAPI> _Nullable)defaultManager;
- (id<ParedAssetSetConfigurationAPI> _Nullable)getAssetSet:(NSString *)name;
- (ParedAssetSetUsages *_Nullable)
    getAssetSetUsagesForUsageAlias:(NSString *)alias
                   usageAliasValue:(NSString *)value;
@end

// Asset set configuration is separate from the class used to open assets
@protocol ParedAssetSetUsageAPI <NSObject>
- (NSArray<NSString *> *_Nullable)usageTypes;
// A missing restriction allows any value; a present key lists allowed values
// Apple silently drops unsupported values when selecting assets
- (NSDictionary<NSString *, NSArray<NSString *> *> *_Nullable)usageValues;
@end

@protocol ParedAssetSetConfigurationAPI <ParedAssetSetUsageAPI>
- (NSString *_Nullable)autoAssetType;
@end

// Values encoded by the native subscription's NSCoding implementation
@protocol ParedSubscriptionValuesAPI <NSObject>
- (NSString *_Nullable)name;
- (ParedAssetSetUsages *_Nullable)assetSets;
- (ParedStringValues *_Nullable)usageAliases;
- (NSDate *_Nullable)expiration;
@end

// The initializer retains its inputs despite the properties being marked copy
// Copy strings and nested dictionaries before passing them in
//
// Native validation checks usage names and alias existence, but accepts empty
// scopes and does not check every value. Validate those ourselves first
//
// Subscriptions have no expiration unless one is supplied. The subscriber name
// belongs to the operation request, not the subscription
//
// XPC needs the native object: its secure decoder expects a name and at least
// one scope, with NSDictionary/NSString contents and an optional NSDate
@protocol ParedSubscriptionAPI <ParedSubscriptionValuesAPI, NSSecureCoding>
- (instancetype _Nullable)initWithName:(NSString *_Nullable)name
                             assetSets:(ParedAssetSetUsages *_Nullable)sets
                          usageAliases:(ParedStringValues *_Nullable)aliases;
- (BOOL)isValid:(id<ParedConfigurationManagerAPI> _Nullable)configurationManager
          error:(NSError *_Nullable *_Nullable)error;
@end

// Use Apple's interface to preserve the allowed classes for nested subscription
// objects. Completion receives NSError or nil
@protocol ParedServiceInterfaceAPI <NSObject>
+ (NSXPCInterface *_Nullable)defaultInterface;
@end

@protocol ParedServiceAPI <NSObject>
// Omit SubscriptionUser to use the connection's effective user; Subscriber
// names identify requests within that user. Set UserInitiated explicitly
- (oneway void)operationWithConfig:(NSDictionary<NSString *, id> *)configuration
                        completion:(void (^)(NSError *_Nullable))completion;
@end

// The query locks the latest downloaded instance, then releases it before
// returning. A release error can accompany a status object; reject that result
@protocol ParedAutoAssetManagerAPI <NSObject>
+ (id<ParedAssetSetStatusAPI> _Nullable)
    latestStatusForClients:(NSString *)name
                     error:(NSError *_Nullable *_Nullable)error;
@end

// Configured and downloaded entries have different classes
// A vending instance matches the configured entries, but its files can still
// become unavailable after the query returns
@protocol ParedAssetSetStatusObjectsAPI <NSObject>
- (NSString *_Nullable)latestDownloadedAtomicInstance;
- (NSArray<MAAutoAssetSetEntry *> *_Nullable)configuredAssetEntries;
- (NSArray<id<ParedDownloadedEntryAPI>> *_Nullable)
    latestDowloadedAtomicInstanceEntries;
@end

// Keep scalar signatures separate so unsupported counters have a distinct error
@protocol ParedAssetSetStatusScalarsAPI <NSObject>
- (int64_t)downloadedNetworkBytes;
- (int64_t)downloadedFilesystemBytes;
- (BOOL)vendingAtomicInstanceForConfiguredEntries;
@end

@protocol ParedAssetSetStatusAPI <ParedAssetSetStatusObjectsAPI,
                                  ParedAssetSetStatusScalarsAPI>
@end

// Only downloaded entries have fullAssetSelector; configured entries use
// assetSelector instead
@protocol ParedDownloadedEntryAPI <NSObject>
- (NSString *_Nullable)assetID;
- (id<ParedAutoAssetSelectorAPI> _Nullable)fullAssetSelector;
@end

// Selectors can have missing fields; require a type, specifier, and version
// before exposing a downloaded asset
@protocol ParedAutoAssetSelectorAPI <NSObject>
- (NSString *_Nullable)assetType;
- (NSString *_Nullable)assetSpecifier;
- (NSString *_Nullable)assetVersion;
@end

NS_ASSUME_NONNULL_END
