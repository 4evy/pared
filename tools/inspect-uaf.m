// Repeat private-API inspection after an OS update, using the current catalog
// Read configuration/status and securely archive native subscription objects
// No subscription-service connection or reset/subscribe/unsubscribe is sent
// Status reads can take short-lived MobileAsset locks and emit system logs
//
// clang-format off
// Build and run from the repository root:
// xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
//   -ISources/AssetBridge/include Sources/AssetBridge/AssetBridge.m \
//   tools/inspect-uaf.m -o /tmp/inspect-uaf
// /tmp/inspect-uaf Sources/Pared/Resources/catalog.json > /tmp/uaf-report.json
// clang-format on
//
// Exit 0 means report collection succeeded, not that every query succeeded
// Inspect bridgeInterfaceAvailable, per-set errors, and validation/archive
// fields; setup failures exit nonzero and raw local reports are not fixtures
#import "AssetBridge.h"
#import <objc/runtime.h>

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@protocol ParedInspectableSubscription <NSObject, NSSecureCoding>
- (instancetype)initWithName:(NSString *)name
                   assetSets:(NSDictionary *)sets
                usageAliases:(NSDictionary *)aliases;
- (NSString *)name;
- (NSDictionary *)assetSets;
- (NSDictionary *)usageAliases;
- (NSDate *)expiration;
@end

static BOOL ObjectGetterAvailable(id object, SEL selector) {
  Method method = class_getInstanceMethod(object_getClass(object), selector);
  if (!method) {
    return NO;
  }
  NSMethodSignature *signature =
      [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
  return !strcmp(signature.methodReturnType, "@") &&
         signature.numberOfArguments == 2;
}

static NSDictionary *ErrorDetails(NSError *error) {
  return error ? @{
    @"domain" : error.domain,
    @"code" : @(error.code),
    @"description" : error.localizedDescription
  }
               : @{};
}

static NSDictionary *Methods(NSString *name) {
  Class type = NSClassFromString(name);
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  for (int meta = 0; meta < 2; meta++) {
    unsigned int count = 0;
    Method *methods =
        class_copyMethodList(meta ? object_getClass(type) : type, &count);
    for (unsigned int i = 0; i < count; i++) {
      NSString *key =
          [NSString stringWithFormat:@"%c%s", meta ? '+' : '-',
                                     sel_getName(method_getName(methods[i]))];
      result[key] = @(method_getTypeEncoding(methods[i]));
    }
    free(methods);
  }
  return result;
}

static NSArray<NSString *> *ClassNames(NSSet *classes) {
  NSMutableArray *names = [NSMutableArray array];
  for (Class type in classes) {
    [names addObject:NSStringFromClass(type)];
  }
  return [names sortedArrayUsingSelector:@selector(compare:)];
}

static NSDictionary *Snapshot(ParedLocalDownloadStatus *status) {
  NSMutableArray *assets = [NSMutableArray array];
  for (ParedDownloadedAsset *asset in status.downloadedAssets) {
    [assets addObject:@{
      @"assetID" : asset.assetID,
      @"assetType" : asset.assetType,
      @"assetSpecifier" : asset.assetSpecifier,
      @"assetVersion" : asset.assetVersion
    }];
  }
  return @{
    @"latestDownloadedAtomicInstance" : status.latestDownloadedAtomicInstance
        ?: NSNull.null,
    @"configuredAssetEntries" : @(status.configuredAssetEntries),
    @"latestDowloadedAtomicInstanceEntries" :
        @(status.latestDowloadedAtomicInstanceEntries),
    @"downloadedNetworkBytes" : @(status.downloadedNetworkBytes),
    @"downloadedFilesystemBytes" : @(status.downloadedFilesystemBytes),
    @"vendingAtomicInstanceForConfiguredEntries" :
        @(status.vendingAtomicInstanceForConfiguredEntries),
    @"downloadedAssets" : assets
  };
}

static NSDictionary *InspectMethods(void) {
  NSMutableDictionary *methods = [NSMutableDictionary dictionary];
  for (NSString *name in @[
         @"UAFConfigurationManager", @"UAFAssetSetConfiguration",
         @"UAFAssetSetSubscription", @"UAFXPCProxyServiceInterface",
         @"UAFAutoAssetManager", @"MAAutoAssetSetStatus",
         @"MAAutoAssetSetAtomicEntry", @"MAAutoAssetSelector"
       ]) {
    methods[name] = Methods(name);
  }
  return methods;
}

static NSDictionary *InspectAssetSets(NSDictionary *types) {
  NSMutableDictionary *sets = [NSMutableDictionary dictionary];
  for (NSString *name in types) {
    NSError *error = nil;
    ParedLocalDownloadStatus *status = ParedLocalStatus(name, &error);
    sets[name] = @{
      @"catalogType" : types[name],
      @"runtimeType" : ParedAssetTypeForSet(name) ?: NSNull.null,
      @"usageTypes" : ParedUsageTypesForSet(name) ?: (id)NSNull.null,
      @"snapshot" : status ? Snapshot(status) : (id)NSNull.null,
      @"error" : ErrorDetails(error)
    };
  }
  return sets;
}

static id SecureArchiveRoundTrip(id<NSObject, NSSecureCoding> object,
                                 NSUInteger *archiveBytes, NSError **error) {
  NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:object
                                          requiringSecureCoding:YES
                                                          error:error];
  if (archiveBytes) {
    *archiveBytes = archive.length;
  }
  return archive ? [NSKeyedUnarchiver unarchivedObjectOfClass:[object class]
                                                     fromData:archive
                                                        error:error]
                 : nil;
}

// Inspects the transport object locally without connecting to the daemon
static void InspectNativeSubscription(ParedAssetSubscription *validated,
                                      NSDictionary *recovery,
                                      NSMutableDictionary *details) {
  NSError *error = nil;
  NSDictionary *usages = recovery[@"assetSetUsages"] ?: @{};
  NSDictionary *aliases = recovery[@"usageAliases"];
  // The bridge verified this initializer before the diagnostic call
  Class type = NSClassFromString(@"UAFAssetSetSubscription");
  id<ParedInspectableSubscription> native =
      [(id<ParedInspectableSubscription>)[type alloc]
          initWithName:recovery[@"name"]
             assetSets:usages
          usageAliases:aliases];
  // Inspect ownership without mutating caller inputs or sending requests
  BOOL ownershipAvailable =
      ObjectGetterAvailable(native, @selector(name)) &&
      ObjectGetterAvailable(native, @selector(assetSets)) &&
      ObjectGetterAvailable(native, @selector(usageAliases)) &&
      ObjectGetterAvailable(native, @selector(expiration));
  details[@"nativeInputOwnershipAvailable"] = @(ownershipAvailable);
  if (ownershipAvailable) {
    details[@"nativeRetainsName"] = @([native name] == recovery[@"name"]);
    details[@"nativeRetainsAssetSets"] = @([native assetSets] == usages);
    details[@"nativeRetainsUsageAliases"] = @([native usageAliases] == aliases);
    details[@"nativeHasExpiration"] = @([native expiration] != nil);
  }
  // Read the opaque wrapper only for diagnostics; callers use the public
  // typed operations, which unwrap this value at the XPC boundary
  Ivar nativeIvar =
      class_getInstanceVariable(ParedAssetSubscription.class, "_native");
  id<ParedInspectableSubscription> bridgeNative =
      nativeIvar ? object_getIvar(validated, nativeIvar) : nil;
  BOOL snapshotAvailable =
      ObjectGetterAvailable(bridgeNative, @selector(name)) &&
      ObjectGetterAvailable(bridgeNative, @selector(assetSets)) &&
      ObjectGetterAvailable(bridgeNative, @selector(usageAliases));
  details[@"bridgeInputSnapshotAvailable"] = @(snapshotAvailable);
  if (snapshotAvailable) {
    NSDictionary *snapshotSets = [bridgeNative assetSets];
    NSDictionary *snapshotAliases = [bridgeNative usageAliases];
    BOOL nestedCopies = YES;
    for (NSString *set in usages) {
      nestedCopies &=
          snapshotSets[set] != usages[set] &&
          ![snapshotSets[set] isKindOfClass:NSMutableDictionary.class];
    }
    details[@"bridgeInputSnapshot"] = @{
      @"nameEqual" : @([[bridgeNative name] isEqual:recovery[@"name"]]),
      @"assetSetsEqual" : @([snapshotSets isEqual:usages]),
      @"usageAliasesEqual" : @([snapshotAliases isEqual:aliases]),
      @"assetSetsCopied" : @(snapshotSets != usages),
      @"usageAliasesCopied" : @(snapshotAliases != aliases),
      @"nestedUsagesCopiedAndImmutable" : @(nestedCopies),
      @"assetSetsImmutable" :
          @(![snapshotSets isKindOfClass:NSMutableDictionary.class]),
      @"usageAliasesImmutable" :
          @(![snapshotAliases isKindOfClass:NSMutableDictionary.class])
    };
    error = nil;
    id bridgeDecoded = SecureArchiveRoundTrip(bridgeNative, NULL, &error);
    details[@"bridgeNativeEqual"] = @([native isEqual:bridgeNative]);
    details[@"bridgeSecureArchiveRoundTripEqual"] =
        @([bridgeNative isEqual:bridgeDecoded]);
    details[@"bridgeSecureArchiveError"] = ErrorDetails(error);
  }
  error = nil;
  NSUInteger archiveBytes = 0;
  id decoded = SecureArchiveRoundTrip(native, &archiveBytes, &error);
  details[@"secureArchiveBytes"] = @(archiveBytes);
  details[@"secureArchiveRoundTripEqual"] = @([native isEqual:decoded]);
  details[@"secureArchiveError"] = ErrorDetails(error);
}

static NSDictionary *InspectRecovery(NSDictionary *recovery) {
  NSDictionary *usages = recovery[@"assetSetUsages"] ?: @{};
  NSDictionary *aliases = recovery[@"usageAliases"];
  NSMutableDictionary *resolved = [NSMutableDictionary dictionary];
  for (NSString *alias in aliases) {
    resolved[alias] =
        ParedResolveUsageAlias(alias, aliases[alias]) ?: (id)NSNull.null;
  }
  NSError *error = nil;
  ParedAssetSubscription *validated =
      ParedSubscription(recovery[@"name"], usages, aliases, &error);
  NSMutableDictionary *details = [@{
    @"validated" : @(validated != nil),
    @"validationError" : ErrorDetails(error),
    @"resolvedAliases" : resolved
  } mutableCopy];
  if (validated) {
    InspectNativeSubscription(validated, recovery, details);
  }
  return details;
}

static NSDictionary *InspectRecoveries(NSDictionary *features) {
  NSMutableDictionary *recoveries = [NSMutableDictionary dictionary];
  for (NSString *name in features) {
    NSDictionary *recovery = features[name][@"recovery"];
    if (recovery) {
      recoveries[name] = InspectRecovery(recovery);
    }
  }
  return recoveries;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) {
      fprintf(stderr,
              "Usage: inspect-uaf Sources/Pared/Resources/catalog.json\n");
      return 64;
    }
    if (!dlopen("/System/Library/PrivateFrameworks/"
                "UnifiedAssetFramework.framework/UnifiedAssetFramework",
                RTLD_NOW)) {
      fprintf(stderr, "Cannot load UnifiedAssetFramework: %s\n", dlerror());
      return 69;
    }
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:@(argv[1])
                                          options:0
                                            error:&error];
    NSDictionary *catalog =
        data ? [NSJSONSerialization JSONObjectWithData:data
                                               options:0
                                                 error:&error]
             : nil;
    if (![catalog isKindOfClass:NSDictionary.class] ||
        ![catalog[@"assetTypes"] isKindOfClass:NSDictionary.class] ||
        ![catalog[@"features"] isKindOfClass:NSDictionary.class]) {
      fprintf(stderr, "Cannot read catalog: %s\n",
              error.description.UTF8String ?: "unknown structure");
      return 1;
    }
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"os"] = NSProcessInfo.processInfo.operatingSystemVersionString;
#if defined(__arm64__)
    report[@"architecture"] = @"arm64";
#else
    report[@"architecture"] = @"other";
#endif
    report[@"methods"] = InspectMethods();
    NSXPCInterface *interface = ParedServiceInterface();
    report[@"bridgeInterfaceAvailable"] = @(interface != nil);
    if (interface) {
      SEL operation = NSSelectorFromString(@"operationWithConfig:completion:");
      struct objc_method_description method = protocol_getMethodDescription(
          interface.protocol, operation, YES, YES);
      report[@"xpc"] = @{
        @"protocol" : @(protocol_getName(interface.protocol)),
        @"operationEncoding" : @(method.types),
        @"requestClasses" : ClassNames([interface classesForSelector:operation
                                                       argumentIndex:0
                                                             ofReply:NO]),
        @"replyClasses" : ClassNames([interface classesForSelector:operation
                                                     argumentIndex:0
                                                           ofReply:YES])
      };
    }
    NSMutableDictionary *types = [catalog[@"assetTypes"] mutableCopy];
    [types addEntriesFromDictionary:catalog[@"recoveryAssetTypes"] ?: @{}];
    report[@"assetSets"] = InspectAssetSets(types);
    report[@"recoveries"] = InspectRecoveries(catalog[@"features"]);
    data = [NSJSONSerialization
        dataWithJSONObject:report
                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                     error:&error];
    if (!data) {
      fprintf(stderr, "Cannot encode report: %s\n",
              error.description.UTF8String);
      return 1;
    }
    [NSFileHandle.fileHandleWithStandardOutput writeData:data];
    puts("");
    // Query errors are observations in the report; only probe setup failures
    // prevent collecting evidence about partially available private interfaces
    return 0;
  }
}
