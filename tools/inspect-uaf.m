// Read configuration and status, and check subscription serialization locally
// No requests are sent to the subscription daemon. Status reads briefly lock
// assets and may produce system logs
//
// clang-format off
// Build and run from the repository root:
// xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
//   -ISources/AssetBridge/include Sources/AssetBridge/*.m \
//   tools/inspect-uaf.m -o /tmp/inspect-uaf
// /tmp/inspect-uaf Sources/Pared/Resources/catalog.json > /tmp/uaf-report.json
// clang-format on
//
// Exit 0 means the report was collected; individual queries can still fail
// Check the interface, validation, archive, and per-set error fields
#import "../Sources/AssetBridge/BridgeInternal.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

// Remove the image slide so implementation addresses stay useful across runs
// Looking up a method does not call it
static NSDictionary *Implementations(NSString *name) {
  Class type = NSClassFromString(name);
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  for (int meta = 0; meta < 2; meta++) {
    unsigned int count = 0;
    Method *methods =
        class_copyMethodList(meta ? object_getClass(type) : type, &count);
    for (unsigned int i = 0; i < count; i++) {
      const void *implementation =
          (const void *)method_getImplementation(methods[i]);
      Dl_info info;
      if (!dladdr(implementation, &info) || !info.dli_fname) {
        continue;
      }
      for (uint32_t image = 0; image < _dyld_image_count(); image++) {
        if (strcmp(_dyld_get_image_name(image), info.dli_fname)) {
          continue;
        }
        uintptr_t address =
            (uintptr_t)implementation - _dyld_get_image_vmaddr_slide(image);
        NSString *key =
            [NSString stringWithFormat:@"%c%s", meta ? '+' : '-',
                                       sel_getName(method_getName(methods[i]))];
        result[key] = @{
          @"image" : @(info.dli_fname),
          @"address" :
              [NSString stringWithFormat:@"0x%llx", (unsigned long long)address]
        };
        break;
      }
    }
    free(methods);
  }
  return result;
}

// Properties can name classes that method signatures omit; collection contents
// still need their own checks
static NSDictionary *Properties(NSString *name) {
  unsigned int count = 0;
  objc_property_t *properties =
      class_copyPropertyList(NSClassFromString(name), &count);
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  for (unsigned int i = 0; i < count; i++) {
    result[@(property_getName(properties[i]))] =
        @(property_getAttributes(properties[i]));
  }
  free(properties);
  return result;
}

// Record which framework binaries are loaded; selectors alone cannot identify
// an implementation
static NSDictionary *FrameworkImages(void) {
  NSMutableDictionary *images = [NSMutableDictionary dictionary];
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const char *path = _dyld_get_image_name(i);
    if (!strstr(path, "/UnifiedAssetFramework.framework/") &&
        !strstr(path, "/MobileAsset.framework/")) {
      continue;
    }
    const struct mach_header *header = _dyld_get_image_header(i);
    if (header->magic != MH_MAGIC_64) {
      continue;
    }
    const struct load_command *command =
        (const void *)((const struct mach_header_64 *)header + 1);
    for (uint32_t j = 0; j < header->ncmds; j++) {
      if (command->cmd == LC_UUID) {
        const struct uuid_command *uuid = (const void *)command;
        images[@(path)] =
            [[NSUUID alloc] initWithUUIDBytes:uuid->uuid].UUIDString;
        break;
      }
      command = (const void *)((const char *)command + command->cmdsize);
    }
  }
  return images;
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

// Collect each class's methods, implementations, and properties in one place
typedef NS_OPTIONS(NSUInteger, ParedClassInspection) {
  ParedClassMethods = 1 << 0,
  ParedClassImplementations = 1 << 1,
  ParedClassProperties = 1 << 2,
  ParedClassAll = ParedClassMethods | ParedClassImplementations |
      ParedClassProperties
};

static const struct {
  __unsafe_unretained NSString *name;
  ParedClassInspection observations;
} kParedInspectedClasses[] = {
    {@"UAFConfigurationManager", ParedClassMethods | ParedClassImplementations},
    {@"UAFAssetSetConfiguration", ParedClassAll},
    {@"UAFAssetConfiguration", ParedClassMethods | ParedClassImplementations},
    {@"UAFAssetExpansion", ParedClassMethods | ParedClassImplementations},
    {@"UAFCommonUtilities", ParedClassMethods | ParedClassImplementations},
    {@"UAFAssetSetSubscription", ParedClassAll},
    {@"UAFXPCProxyServiceInterface",
     ParedClassMethods | ParedClassImplementations},
    {@"UAFXPCService", ParedClassImplementations},
    {@"UAFAssetSetManager", ParedClassImplementations},
    {@"UAFSubscriptionStoreManager", ParedClassImplementations},
    {@"UAFUserManager", ParedClassImplementations},
    {@"UAFAutoAssetManager", ParedClassMethods | ParedClassImplementations},
    {@"MAAutoAssetSet", ParedClassImplementations},
    {@"MAAutoAssetSetStatus", ParedClassAll},
    {@"MAAutoAssetSetAtomicEntry", ParedClassAll},
    {@"MAAutoAssetSetEntry", ParedClassImplementations | ParedClassProperties},
    {@"MAAutoAssetSelector", ParedClassAll}};

static NSDictionary *InspectClasses(ParedClassInspection observation,
                                    NSDictionary *(*inspect)(NSString *)) {
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  for (size_t i = 0;
       i < sizeof(kParedInspectedClasses) / sizeof(kParedInspectedClasses[0]);
       i++) {
    if (kParedInspectedClasses[i].observations & observation) {
      NSString *name = kParedInspectedClasses[i].name;
      result[name] = inspect(name);
    }
  }
  return [result copy];
}

static NSDictionary *InspectAssetSets(NSDictionary *types) {
  NSMutableDictionary *sets = [NSMutableDictionary dictionary];
  for (NSString *name in types) {
    NSError *error = nil;
    ParedLocalDownloadStatus *status = ParedLocalStatus(name, &error);
    NSArray<NSString *> *usages = ParedUsageTypesForSet(name);
    // The bridge checked the manager's lookup methods. Check the restriction
    // getter too; nil means unrestricted
    id<ParedConfigurationManagerAPI> manager =
        usages ? [(id<ParedConfigurationManagerAPI>)NSClassFromString(
                     @"UAFConfigurationManager") defaultManager]
               : nil;
    id<ParedAssetSetConfigurationAPI> configuration =
        [manager getAssetSet:name];
    BOOL restrictionsAvailable =
        ParedHasMethod(configuration, @selector(usageValues),
                       @protocol(ParedAssetSetUsageAPI));
    id restrictions = restrictionsAvailable ? [configuration usageValues] : nil;
    sets[name] = @{
      @"catalogType" : types[name],
      @"runtimeType" : ParedAssetTypeForSet(name) ?: NSNull.null,
      @"usageTypes" : usages ?: (id)NSNull.null,
      @"usageValuesAvailable" : @(restrictionsAvailable),
      @"usageValues" : restrictions ?: NSNull.null,
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

// Inspect subscriptions locally without connecting to the daemon
static void InspectNativeSubscription(ParedAssetSubscription *validated,
                                      NSDictionary *recovery,
                                      NSMutableDictionary *details) {
  NSError *error = nil;
  NSDictionary *usages = recovery[@"assetSetUsages"] ?: @{};
  NSDictionary *aliases = recovery[@"usageAliases"];
  // The bridge already checked this initializer's signature
  Class type = NSClassFromString(@"UAFAssetSetSubscription");
  id<ParedSubscriptionAPI> native =
      [(id<ParedSubscriptionAPI>)[type alloc] initWithName:recovery[@"name"]
                                                 assetSets:usages
                                              usageAliases:aliases];
  // Compare references to see which inputs Apple retained
  BOOL ownershipAvailable =
      ParedHasDeclaredMethods(native, @protocol(ParedSubscriptionValuesAPI));
  details[@"nativeInputOwnershipAvailable"] = @(ownershipAvailable);
  if (ownershipAvailable) {
    details[@"nativeRetainsName"] = @([native name] == recovery[@"name"]);
    details[@"nativeRetainsAssetSets"] = @([native assetSets] == usages);
    details[@"nativeRetainsUsageAliases"] = @([native usageAliases] == aliases);
    details[@"nativeHasExpiration"] = @([native expiration] != nil);
  }
  // Read the wrapped object for this diagnostic only; callers use the bridge's
  // public operations
  Ivar nativeIvar =
      class_getInstanceVariable(ParedAssetSubscription.class, "_native");
  id<ParedSubscriptionAPI> bridgeNative =
      nativeIvar ? object_getIvar(validated, nativeIvar) : nil;
  BOOL snapshotAvailable = ParedHasDeclaredMethods(
      bridgeNative, @protocol(ParedSubscriptionValuesAPI));
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
    report[@"methods"] = InspectClasses(ParedClassMethods, Methods);
    report[@"implementations"] =
        InspectClasses(ParedClassImplementations, Implementations);
    report[@"properties"] = InspectClasses(ParedClassProperties, Properties);
    report[@"frameworkImages"] = FrameworkImages();
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
    // Keep query errors in the report; only setup failures prevent collection
    return 0;
  }
}
