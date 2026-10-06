// Exercise the live bridge and an isolated XPC server with Apple's interface
// No request is sent to Apple's subscription daemon
// Link the product sources and expose the private compiler-encoding guards
#import "../Sources/AssetBridge/BridgeInternal.h"
#import <dlfcn.h>
#import <fcntl.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdio.h>

static atomic_uint checks;
#define Check(...)                                                             \
  do {                                                                         \
    atomic_fetch_add(&checks, 1);                                              \
    if (!(__VA_ARGS__)) {                                                      \
      fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__);           \
      abort();                                                                 \
    }                                                                          \
  } while (0)

@protocol InspectSubscription <ParedSubscriptionAPI>
- (NSString *)name;
- (ParedAssetSetUsages *)assetSets;
- (ParedStringValues *)usageAliases;
@end

@interface Capture : NSObject <ParedServiceAPI, NSXPCListenerDelegate>
@property(nonatomic, strong) NSDictionary *configuration;
@property(nonatomic, strong) NSError *replyError;
@property(nonatomic, strong) NSMutableArray<NSXPCConnection *> *connections;
@property(nonatomic, strong) dispatch_semaphore_t received;
@property(nonatomic) BOOL dropReplies;
@end
@implementation Capture
- (instancetype)init {
  if ((self = [super init])) {
    _connections = [NSMutableArray array];
  }
  return self;
}
- (oneway void)operationWithConfig:(NSDictionary *)configuration
                        completion:(void (^)(NSError *))completion {
  self.configuration = configuration;
  if (self.received) {
    dispatch_semaphore_signal(self.received);
  }
  if (!self.dropReplies) {
    completion(self.replyError);
  }
}
- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)connection {
  (void)listener;
  connection.exportedInterface = ParedServiceInterface();
  connection.exportedObject = self;
  @synchronized(self) {
    [self.connections addObject:connection];
  }
  [connection resume];
  return YES;
}
@end

@interface FakeSelector : NSObject <ParedAutoAssetSelectorAPI>
@property(nonatomic, strong) NSString *assetType;
@property(nonatomic, strong) NSString *assetSpecifier;
@property(nonatomic, strong) NSString *assetVersion;
@end
@implementation FakeSelector
@end
@interface FakeEntry : NSObject <ParedDownloadedEntryAPI>
@property(nonatomic, strong) NSString *assetID;
@property(nonatomic, strong) id<ParedAutoAssetSelectorAPI> fullAssetSelector;
@end
@implementation FakeEntry
@end
@interface FakeStatus : NSObject <ParedAssetSetStatusAPI>
@property(nonatomic, strong) NSString *latestDownloadedAtomicInstance;
@property(nonatomic, strong) NSArray *configuredAssetEntries;
@property(nonatomic, strong) NSArray *latestDowloadedAtomicInstanceEntries;
@property(nonatomic) int64_t downloadedNetworkBytes;
@property(nonatomic) int64_t downloadedFilesystemBytes;
@property(nonatomic) BOOL vendingAtomicInstanceForConfiguredEntries;
@end
@implementation FakeStatus
@end
@interface WrongScalar : NSObject
- (id)downloadedNetworkBytes;
@end
@implementation WrongScalar
- (id)downloadedNetworkBytes {
  abort();
}
@end

@interface FakeSet : NSObject <ParedAssetSetConfigurationAPI>
@property(nonatomic, strong) NSString *autoAssetType;
@property(nonatomic, strong) NSArray<NSString *> *usageTypes;
@property(nonatomic, strong) NSDictionary *usageValues;
@end
@implementation FakeSet
@end
@interface FakeManager : NSObject <ParedConfigurationManagerAPI>
@property(nonatomic, strong) id<ParedAssetSetConfigurationAPI> set;
@property(nonatomic, strong) ParedAssetSetUsages *alias;
@end
@implementation FakeManager
+ (id<ParedConfigurationManagerAPI>)defaultManager {
  return [self new];
}
- (id<ParedAssetSetConfigurationAPI>)getAssetSet:(NSString *)name {
  (void)name;
  return self.set;
}
- (ParedAssetSetUsages *)getAssetSetUsagesForUsageAlias:(NSString *)alias
                                        usageAliasValue:(NSString *)value {
  (void)alias;
  (void)value;
  return self.alias;
}
@end

static NSArray<NSDictionary *> *Recoveries(NSDictionary *catalog) {
  NSMutableArray *result = [NSMutableArray array];
  for (NSString *key in [catalog[@"features"] allKeys]) {
    id recovery = catalog[@"features"][key][@"recovery"];
    if (recovery) {
      [result addObject:recovery];
    }
  }
  return result;
}

static ParedAssetSubscription *Subscription(NSDictionary *recovery) {
  NSError *error = nil;
  ParedAssetSubscription *object =
      ParedSubscription(recovery[@"name"], recovery[@"assetSetUsages"] ?: @{},
                        recovery[@"usageAliases"], &error);
  Check(object != nil && error == nil);
  return object;
}

static id<InspectSubscription> Native(ParedAssetSubscription *object) {
  return object_getIvar(object, class_getInstanceVariable(
                                    ParedAssetSubscription.class, "_native"));
}

static void MalformedInputs(NSDictionary *recovery) {
  Capture *capture = [Capture new];
  ParedAssetSubscription *valid = Subscription(recovery);
  void (^completion)(NSError *) = ^(NSError *error) {
    (void)error;
    abort();
  };
  NSArray *invalid = @[
    NSNull.null, @42, @"", @[], @{}, [NSObject new], @[ @"" ], @[ @42 ],
    @{@"set" : NSNull.null},
    @{@42 : @{@"usage" : @"ENABLED"}},
    @{@"set" : @{@"usage" : @42}},
    @{@"set" : @{@"usage" : @"DISABLED"}}
  ];
  for (id value in invalid) {
    NSError *error = nil;
    Check(!ParedSubscription(value, @{}, @{}, &error) && error);
    error = nil;
    Check(!ParedSubscription(@"invalid", value, @{}, &error) && error);
    error = nil;
    Check(!ParedSubscription(@"invalid", @{}, value, &error) && error);
    error = nil;
    Check(!ParedPerformReset(capture, value, completion, &error) && error);
    error = nil;
    Check(!ParedPerformSubscribe(capture, value, @[ valid ], completion,
                                 &error) &&
          error);
    error = nil;
    Check(!ParedPerformSubscribe(capture, @"test", value, completion, &error) &&
          error);
    error = nil;
    Check(
        !ParedPerformUnsubscribe(capture, @"test", value, completion, &error) &&
        error);
    error = nil;
    Check(!ParedLocalStatus(value, &error) && error);
    Check(!ParedAssetTypeForSet(value));
    Check(!ParedUsageTypesForSet(value));
    Check(!ParedResolveUsageAlias(value, @"missing"));
    Check(capture.configuration == nil);
  }
  NSError *error = nil;
  Check(!ParedPerformSubscribe(capture, @"test", @[ valid, valid ], completion,
                               &error) &&
        error);
  Check(!ParedPerformSubscribe(capture, @"test", (id) @[ [NSObject new] ],
                               completion, &error));
  id missing = nil;
  void (^missingCompletion)(NSError *) = nil;
  Check(!ParedPerformReset(missing, @[ @"test" ], completion, &error));
  Check(!ParedPerformReset(capture, @[ @"test" ], missingCompletion, &error));
  Check(
      !ParedPerformSubscribe(missing, @"test", @[ valid ], completion, &error));
  Check(!ParedPerformSubscribe(capture, @"test", @[ valid ], missingCompletion,
                               &error));
  Check(!ParedPerformUnsubscribe(missing, @"test", @[ @"test" ], completion,
                                 &error));
  Check(!ParedPerformUnsubscribe(capture, @"test", @[ @"test" ],
                                 missingCompletion, &error));
  Check(capture.configuration == nil);
}

static void Ownership(NSDictionary *recovery) {
  NSMutableString *name = [recovery[@"name"] mutableCopy];
  NSMutableDictionary *aliases = [NSMutableDictionary dictionary];
  for (NSString *key in recovery[@"usageAliases"]) {
    aliases[key] = [recovery[@"usageAliases"][key] mutableCopy];
  }
  NSMutableDictionary *sets = [NSMutableDictionary dictionary];
  for (NSString *key in recovery[@"assetSetUsages"]) {
    NSMutableDictionary *usages = [NSMutableDictionary dictionary];
    for (NSString *usage in recovery[@"assetSetUsages"][key]) {
      usages[usage] = [recovery[@"assetSetUsages"][key][usage] mutableCopy];
    }
    sets[key] = usages;
  }
  NSError *error = nil;
  ParedAssetSubscription *subscription =
      ParedSubscription(name, sets, aliases, &error);
  Check(subscription && !error);
  id<InspectSubscription> native = Native(subscription);
  NSData *before = [NSKeyedArchiver archivedDataWithRootObject:native
                                         requiringSecureCoding:YES
                                                         error:&error];
  Check(before && !error);
  [name setString:@"changed"];
  for (NSMutableString *value in aliases.allValues) {
    [value setString:@"changed"];
  }
  for (NSMutableDictionary *usages in sets.allValues) {
    for (NSMutableString *value in usages.allValues) {
      [value setString:@"DISABLED"];
    }
    [usages removeAllObjects];
  }
  [aliases removeAllObjects];
  [sets removeAllObjects];
  NSData *after = [NSKeyedArchiver archivedDataWithRootObject:native
                                        requiringSecureCoding:YES
                                                        error:&error];
  Check([before isEqual:after] && !error);
  Check([[native name] isEqual:recovery[@"name"]]);
  Capture *capture = [Capture new];
  NSMutableString *subscriber = [@"subscriber" mutableCopy];
  NSMutableString *target = [@"target" mutableCopy];
  NSMutableArray *names = [NSMutableArray arrayWithObjects:target, target, nil];
  Check(ParedPerformUnsubscribe(
      capture, subscriber, names,
      ^(NSError *reply) {
        Check(!reply);
      },
      &error));
  [subscriber setString:@"changed"];
  [target setString:@"changed"];
  [names removeAllObjects];
  Check([capture.configuration[@"Subscriber"] isEqual:@"subscriber"]);
  Check([capture.configuration[@"Subscriptions"] isEqual:@[ @"target" ]]);
}

static void Wire(NSArray<NSDictionary *> *recoveries) {
  Capture *server = [Capture new];
  NSXPCListener *listener = [NSXPCListener anonymousListener];
  listener.delegate = server;
  [listener resume];
  NSXPCConnection *connection =
      [[NSXPCConnection alloc] initWithListenerEndpoint:listener.endpoint];
  connection.remoteObjectInterface = ParedServiceInterface();
  Check(connection.remoteObjectInterface != nil);
  [connection resume];
  NSObject *proxy =
      [connection remoteObjectProxyWithErrorHandler:^(NSError *e) {
        fprintf(stderr, "Unexpected XPC transport error: %s\n",
                e.description.UTF8String);
        abort();
      }];
  NSMutableArray *subscriptions = [NSMutableArray array];
  for (NSDictionary *recovery in recoveries) {
    [subscriptions addObject:Subscription(recovery)];
  }
  for (NSUInteger i = 0; i < 90; i++) {
    @autoreleasepool {
      server.replyError =
          i % 2 ? [NSError errorWithDomain:@"test.daemon"
                                      code:7
                                  userInfo:@{
                                    @"nested" : [NSError
                                        errorWithDomain:@"test.underlying"
                                                   code:8
                                               userInfo:nil]
                                  }]
                : nil;
      dispatch_semaphore_t done = dispatch_semaphore_create(0);
      void (^completion)(NSError *) = ^(NSError *reply) {
        Check([reply.domain isEqual:@"test.daemon"] == (i % 2 != 0));
        if (reply) {
          Check(reply.code == 7);
          Check([reply.userInfo[@"nested"] code] == 8);
        }
        dispatch_semaphore_signal(done);
      };
      NSError *error = nil;
      switch (i % 3) {
      case 0:
        Check(ParedPerformSubscribe(proxy, @"test", subscriptions, completion,
                                    &error));
        break;
      case 1:
        Check(ParedPerformUnsubscribe(proxy, @"test", @[ @"a", @"a", @"b" ],
                                      completion, &error));
        break;
      default:
        Check(ParedPerformReset(proxy, @[ @"b", @"a", @"a" ], completion,
                                &error));
        break;
      }
      Check(!error);
      Check(dispatch_semaphore_wait(
                done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
      NSDictionary *request = server.configuration;
      Check(request[@"SubscriptionUser"] == nil);
      if (i % 3 == 0) {
        NSArray *decoded = request[@"Subscriptions"];
        Check(decoded.count == subscriptions.count);
        for (NSUInteger j = 0; j < decoded.count; j++) {
          Check([decoded[j]
              isKindOfClass:NSClassFromString(@"UAFAssetSetSubscription")]);
          Check([decoded[j] isEqual:Native(subscriptions[j])]);
        }
        Check([request[@"UserInitiated"] isEqual:@YES]);
      } else {
        Check([request[i % 3 == 1 ? @"Subscriptions" : @"AssetSets"]
            isEqual:@[ @"a", @"b" ]]);
      }
    }
  }
  [connection invalidate];
  [listener invalidate];
  for (NSXPCConnection *accepted in server.connections) {
    [accepted invalidate];
  }
}

static void WireFailure(void) {
  Capture *server = [Capture new];
  server.dropReplies = YES;
  server.received = dispatch_semaphore_create(0);
  NSXPCListener *listener = [NSXPCListener anonymousListener];
  listener.delegate = server;
  [listener resume];
  NSXPCConnection *connection =
      [[NSXPCConnection alloc] initWithListenerEndpoint:listener.endpoint];
  connection.remoteObjectInterface = ParedServiceInterface();
  [connection resume];
  dispatch_semaphore_t disconnected = dispatch_semaphore_create(0);
  __block NSError *transportError = nil;
  NSObject *proxy =
      [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        transportError = error;
        dispatch_semaphore_signal(disconnected);
      }];
  NSError *error = nil;
  Check(ParedPerformReset(
      proxy, @[ @"isolated.test" ],
      ^(NSError *reply) {
        (void)reply;
        abort();
      },
      &error));
  Check(!error);
  Check(dispatch_semaphore_wait(
            server.received,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
  Check(dispatch_semaphore_wait(disconnected, DISPATCH_TIME_NOW) != 0);
  @synchronized(server) {
    for (NSXPCConnection *accepted in server.connections) {
      [accepted invalidate];
    }
  }
  Check(dispatch_semaphore_wait(
            disconnected, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) ==
        0);
  Check([transportError isKindOfClass:NSError.class]);
  [connection invalidate];
  [listener invalidate];
  puts("XPC failure: missing reply and interrupted connection observed");
}

static void StatusFaults(void) {
  Class type = NSClassFromString(@"UAFAutoAssetManager");
  Method method =
      class_getClassMethod(type, @selector(latestStatusForClients:error:));
  IMP original = method_getImplementation(method);
  __block id returned = nil;
  __block NSError *returnedError = nil;
  IMP replacement = imp_implementationWithBlock(
      ^id(id object, NSString *name, NSError **error) {
        (void)object;
        (void)name;
        *error = returnedError;
        return returned;
      });
  method_setImplementation(method, replacement);
  NSError *error = nil;
  Check(!ParedLocalStatus(@"test", &error) && error);
  returned = [NSObject new];
  error = nil;
  Check(!ParedLocalStatus(@"test", &error) && error);
  FakeStatus *status = [FakeStatus new];
  status.configuredAssetEntries = @[];
  status.latestDowloadedAtomicInstanceEntries = @[];
  status.downloadedNetworkBytes = INT64_MAX;
  status.downloadedFilesystemBytes = INT64_MIN;
  status.vendingAtomicInstanceForConfiguredEntries = YES;
  returned = status;
  error = nil;
  ParedLocalDownloadStatus *snapshot = ParedLocalStatus(@"test", &error);
  Check(snapshot && !error && snapshot.downloadedNetworkBytes == INT64_MAX &&
        snapshot.downloadedFilesystemBytes == INT64_MIN &&
        snapshot.vendingAtomicInstanceForConfiguredEntries);
  returnedError = [NSError errorWithDomain:@"test.release" code:1 userInfo:nil];
  Check(!ParedLocalStatus(@"test", &error) && error == returnedError);
  returnedError = nil;
  returnedError = (id)NSNull.null;
  error = nil;
  Check(!ParedLocalStatus(@"test", &error) &&
        [error isKindOfClass:NSError.class]);
  returnedError = nil;
  status.configuredAssetEntries = @[ [NSObject new] ];
  error = nil;
  Check(!ParedLocalStatus(@"test", &error) && error);
  status.configuredAssetEntries = @[];
  FakeEntry *entry = [FakeEntry new];
  FakeSelector *selector = [FakeSelector new];
  selector.assetType = [@"type" mutableCopy];
  selector.assetSpecifier = [@"specifier" mutableCopy];
  selector.assetVersion = [@"version" mutableCopy];
  entry.assetID = [@"id" mutableCopy];
  entry.fullAssetSelector = selector;
  status.latestDownloadedAtomicInstance = [@"instance" mutableCopy];
  status.latestDowloadedAtomicInstanceEntries = @[ entry ];
  error = nil;
  snapshot = ParedLocalStatus(@"test", &error);
  Check(snapshot && !error && snapshot.downloadedAssets.count == 1);
  [(NSMutableString *)entry.assetID setString:@"changed"];
  [(NSMutableString *)selector.assetType setString:@"changed"];
  [(NSMutableString *)status.latestDownloadedAtomicInstance
      setString:@"changed"];
  Check([snapshot.downloadedAssets[0].assetID isEqual:@"id"] &&
        [snapshot.downloadedAssets[0].assetType isEqual:@"type"] &&
        [snapshot.latestDownloadedAtomicInstance isEqual:@"instance"]);
  NSArray *invalid = @[ NSNull.null, @42, @"", [NSObject new] ];
  for (id value in invalid) {
    selector.assetVersion = value;
    error = nil;
    Check(!ParedLocalStatus(@"test", &error) && error);
  }
  selector.assetVersion = @"version";
  entry.fullAssetSelector = (id)[NSObject new];
  Check(!ParedLocalStatus(@"test", &error));
  status.latestDowloadedAtomicInstanceEntries = @[ [NSObject new] ];
  Check(!ParedLocalStatus(@"test", &error));
  // Add a fresh override because class_replaceMethod preserves existing types
  entry.fullAssetSelector = selector;
  status.latestDowloadedAtomicInstanceEntries = @[ entry ];
  Method wrong = class_getInstanceMethod(WrongScalar.class,
                                         @selector(downloadedNetworkBytes));
  Class drifted =
      objc_allocateClassPair(FakeStatus.class, "ParedDriftedStatus", 0);
  Check(drifted != Nil);
  Check(class_addMethod(drifted, @selector(downloadedNetworkBytes),
                        method_getImplementation(wrong),
                        method_getTypeEncoding(wrong)));
  objc_registerClassPair(drifted);
  object_setClass(status, drifted);
  error = nil;
  Check(!ParedLocalStatus(@"test", &error) && error);
  object_setClass(status, FakeStatus.class);
  method_setImplementation(method, original);
  imp_removeBlock(replacement);
}

static void ValidationErrorFaults(NSDictionary *recovery) {
  Method method = class_getInstanceMethod(
      NSClassFromString(@"UAFAssetSetSubscription"), @selector(isValid:error:));
  IMP original = method_getImplementation(method);
  __block id returnedError = NSNull.null;
  __block BOOL valid = YES;
  IMP replacement = imp_implementationWithBlock(
      ^BOOL(id object, id manager, NSError **error) {
        (void)object;
        (void)manager;
        *error = returnedError;
        return valid;
      });
  method_setImplementation(method, replacement);
  for (id unsupported in @[ NSNull.null, @"wrong", @42, @{} ]) {
    returnedError = unsupported;
    NSError *error = nil;
    Check(!ParedSubscription(recovery[@"name"],
                             recovery[@"assetSetUsages"] ?: @{},
                             recovery[@"usageAliases"], &error) &&
          [error isKindOfClass:NSError.class]);
  }
  returnedError = nil;
  valid = NO;
  NSError *error = nil;
  Check(!ParedSubscription(recovery[@"name"],
                           recovery[@"assetSetUsages"] ?: @{},
                           recovery[@"usageAliases"], &error) &&
        [error isKindOfClass:NSError.class]);
  returnedError = [NSError errorWithDomain:@"test.validation"
                                      code:1
                                  userInfo:nil];
  error = nil;
  Check(!ParedSubscription(recovery[@"name"],
                           recovery[@"assetSetUsages"] ?: @{},
                           recovery[@"usageAliases"], &error) &&
        error == returnedError);
  method_setImplementation(method, original);
  imp_removeBlock(replacement);
}

static void ConfigurationFaults(void) {
  Method method = class_getClassMethod(
      NSClassFromString(@"UAFConfigurationManager"), @selector(defaultManager));
  IMP original = method_getImplementation(method);
  FakeManager *manager = [FakeManager new];
  FakeSet *set = [FakeSet new];
  set.autoAssetType = @"type";
  set.usageTypes = @[ @"usage" ];
  manager.set = set;
  manager.alias = @{@"set" : @{@"usage" : @"ENABLED"}};
  IMP replacement = imp_implementationWithBlock(^id(id object) {
    (void)object;
    return manager;
  });
  method_setImplementation(method, replacement);
  NSError *error = nil;
  Check(ParedSubscription(@"test", manager.alias, @{}, &error) && !error);
  Check(ParedSubscription(@"test", @{}, @{@"alias" : @"value"}, &error));
  set.usageValues = @{@"usage" : @[ @"DISABLED" ]};
  error = nil;
  Check(!ParedSubscription(@"test", manager.alias, @{}, &error) && error);
  error = nil;
  Check(!ParedSubscription(@"test", @{}, @{@"alias" : @"value"}, &error) &&
        error);
  set.usageValues = @{@"usage" : @[ @"ENABLED" ]};
  error = nil;
  Check(ParedSubscription(@"test", manager.alias, @{}, &error) && !error);
  // A malformed object must be rejected before native isValid: messages it
  set.usageTypes = (id)NSNull.null;
  error = nil;
  Check(!ParedSubscription(@"test", manager.alias, @{}, &error) && error);
  Check(!ParedUsageTypesForSet(@"set"));
  set.usageTypes = @[ @"usage" ];
  for (id restriction in @[ NSNull.null, @42, @"ENABLED", @[], @[ @42 ] ]) {
    set.usageValues = @{@"usage" : restriction};
    error = nil;
    Check(!ParedSubscription(@"test", manager.alias, @{}, &error) && error);
  }
  set.usageValues = nil;
  for (id expansion in @[
         NSNull.null, @42, @[], @{}, @{@"set" : NSNull.null},
         @{@"set" : @{@"usage" : @"DISABLED"}},
         @{@"set" : @{@"missing" : @"ENABLED"}}
       ]) {
    manager.alias = expansion;
    error = nil;
    Check(!ParedSubscription(@"test", @{}, @{@"alias" : @"value"}, &error) &&
          error);
  }
  method_setImplementation(method, original);
  imp_removeBlock(replacement);
}

static void InterfaceFaults(void) {
  Method method =
      class_getClassMethod(NSClassFromString(@"UAFXPCProxyServiceInterface"),
                           @selector(defaultInterface));
  IMP original = method_getImplementation(method);
  __block id returned = [NSObject new];
  IMP replacement = imp_implementationWithBlock(^id(id object) {
    (void)object;
    return returned;
  });
  method_setImplementation(method, replacement);
  Check(!ParedServiceInterface());
  returned = nil;
  Check(!ParedServiceInterface());
  Protocol *protocol = NSProtocolFromString(@"UAFXPCProxyService");
  Check(protocol != nil);
  SEL selector = @selector(operationWithConfig:completion:);
  NSSet *request =
      [NSSet setWithObjects:NSDictionary.class, NSString.class, NSArray.class,
                            NSNumber.class,
                            NSClassFromString(@"UAFAssetSetSubscription"), nil];
  for (Class omitted in request) {
    NSMutableSet *classes = [request mutableCopy];
    [classes removeObject:omitted];
    NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:protocol];
    [interface setClasses:classes
              forSelector:selector
            argumentIndex:0
                  ofReply:NO];
    [interface setClasses:[NSSet setWithObject:NSError.class]
              forSelector:selector
            argumentIndex:0
                  ofReply:YES];
    returned = interface;
    Check(!ParedServiceInterface());
  }
  NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:protocol];
  [interface setClasses:request
            forSelector:selector
          argumentIndex:0
                ofReply:NO];
  [interface setClasses:[NSSet setWithObject:NSString.class]
            forSelector:selector
          argumentIndex:0
                ofReply:YES];
  returned = interface;
  Check(!ParedServiceInterface());
  [interface setClasses:[NSSet setWithObject:NSError.class]
            forSelector:selector
          argumentIndex:0
                ofReply:YES];
  Check(ParedServiceInterface() == interface);
  method_setImplementation(method, original);
  imp_removeBlock(replacement);
}

static void ABIFaults(void) {
  // Stack offsets may differ, but block, pointer and oneway types must agree
  Check(ParedSignatureMatches("Vv32@0:8@16@?24", "Vv64@0:16@32@?48"));
  Check(!ParedSignatureMatches("v32@0:8@16@?24", "Vv32@0:8@16@?24"));
  Check(!ParedSignatureMatches("Vv32@0:8@16@24", "Vv32@0:8@16@?24"));
  Check(!ParedSignatureMatches("q16@0:8", "Q16@0:8"));
  Check(!ParedSignatureMatches("@16@0:8", "q16@0:8"));
  Check(!ParedSignatureMatches("B32@0:8@16^v24", "B32@0:8@16^@24"));
  Check(!ParedSignatureMatches(NULL, "@16@0:8"));
  Check(!ParedSignatureMatches("@16@0:8", NULL));
  struct {
    const char *className;
    const char *selector;
    BOOL meta;
    Protocol *contract;
  } cases[] = {
      {"UAFConfigurationManager", "defaultManager", YES,
       @protocol(ParedConfigurationManagerAPI)},
      {"UAFConfigurationManager", "getAssetSet:", NO,
       @protocol(ParedConfigurationManagerAPI)},
      {"UAFConfigurationManager",
       "getAssetSetUsagesForUsageAlias:usageAliasValue:", NO,
       @protocol(ParedConfigurationManagerAPI)},
      {"UAFAssetSetConfiguration", "autoAssetType", NO,
       @protocol(ParedAssetSetConfigurationAPI)},
      {"UAFAssetSetConfiguration", "usageTypes", NO,
       @protocol(ParedAssetSetConfigurationAPI)},
      {"UAFAssetSetConfiguration", "usageValues", NO,
       @protocol(ParedAssetSetConfigurationAPI)},
      {"UAFAssetSetSubscription", "initWithName:assetSets:usageAliases:", NO,
       @protocol(ParedSubscriptionAPI)},
      {"UAFAssetSetSubscription", "isValid:error:", NO,
       @protocol(ParedSubscriptionAPI)},
      {"UAFAssetSetSubscription", "supportsSecureCoding", YES,
       @protocol(NSSecureCoding)},
      {"UAFAssetSetSubscription", "encodeWithCoder:", NO, @protocol(NSCoding)},
      {"UAFAssetSetSubscription", "initWithCoder:", NO, @protocol(NSCoding)},
      {"UAFXPCProxyServiceInterface", "defaultInterface", YES,
       @protocol(ParedServiceInterfaceAPI)},
      {"UAFAutoAssetManager", "latestStatusForClients:error:", YES,
       @protocol(ParedAutoAssetManagerAPI)},
      {"MAAutoAssetSetStatus", "latestDownloadedAtomicInstance", NO,
       @protocol(ParedAssetSetStatusAPI)},
      {"MAAutoAssetSetStatus", "configuredAssetEntries", NO,
       @protocol(ParedAssetSetStatusAPI)},
      {"MAAutoAssetSetStatus", "latestDowloadedAtomicInstanceEntries", NO,
       @protocol(ParedAssetSetStatusAPI)},
      {"MAAutoAssetSetStatus", "downloadedNetworkBytes", NO,
       @protocol(ParedAssetSetStatusAPI)},
      {"MAAutoAssetSetStatus", "downloadedFilesystemBytes", NO,
       @protocol(ParedAssetSetStatusAPI)},
      {"MAAutoAssetSetStatus", "vendingAtomicInstanceForConfiguredEntries", NO,
       @protocol(ParedAssetSetStatusAPI)},
      {"MAAutoAssetSetAtomicEntry", "assetID", NO,
       @protocol(ParedDownloadedEntryAPI)},
      {"MAAutoAssetSetAtomicEntry", "fullAssetSelector", NO,
       @protocol(ParedDownloadedEntryAPI)},
      {"MAAutoAssetSelector", "assetType", NO,
       @protocol(ParedAutoAssetSelectorAPI)},
      {"MAAutoAssetSelector", "assetSpecifier", NO,
       @protocol(ParedAutoAssetSelectorAPI)},
      {"MAAutoAssetSelector", "assetVersion", NO,
       @protocol(ParedAutoAssetSelectorAPI)},
      {"UAFXPCService", "operationWithConfig:completion:", NO,
       @protocol(ParedServiceAPI)},
  };
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    Class actual = NSClassFromString(@(cases[i].className));
    SEL selector = sel_registerName(cases[i].selector);
    Method method = cases[i].meta ? class_getClassMethod(actual, selector)
                                  : class_getInstanceMethod(actual, selector);
    Check(ParedMethodMatches(method, selector, cases[i].contract,
                             !cases[i].meta));
    Class fault = objc_allocateClassPair(
        NSObject.class,
        [[NSString stringWithFormat:@"ParedABIFault%zu", i] UTF8String], 0);
    Check(fault != Nil);
    Class receiver = cases[i].meta ? object_getClass(fault) : fault;
    Check(class_addMethod(receiver, selector, method_getImplementation(method),
                          "v16@0:8"));
    objc_registerClassPair(fault);
    Method drifted = class_getInstanceMethod(receiver, selector);
    Check(!ParedMethodMatches(drifted, selector, cases[i].contract,
                              !cases[i].meta));
  }
  printf("Live encodings checked and drift rejected: %zu selectors\n",
         sizeof(cases) / sizeof(cases[0]));
}

static unsigned int OpenFiles(void) {
  unsigned int result = 0;
  for (int fd = 0; fd < getdtablesize(); fd++) {
    result += fcntl(fd, F_GETFD) != -1;
  }
  return result;
}

static void ConcurrentReads(NSDictionary *catalog, NSArray *recoveries) {
  NSMutableDictionary *types = [catalog[@"assetTypes"] mutableCopy];
  [types addEntriesFromDictionary:catalog[@"recoveryAssetTypes"] ?: @{}];
  NSArray *sets = types.allKeys;
  NSMutableDictionary *baseline = [NSMutableDictionary dictionary];
  // Warm framework caches and queues before measuring descriptor retention
  for (NSString *set in sets) {
    NSError *error = nil;
    ParedLocalDownloadStatus *status = ParedLocalStatus(set, &error);
    Check((status != nil) != (error != nil));
    baseline[set] = status ?: (id)error;
  }
  unsigned int before = OpenFiles();
  dispatch_apply(
      240, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        @autoreleasepool {
          NSString *set = sets[i % sets.count];
          Check([ParedAssetTypeForSet(set) isEqual:types[set]]);
          Check(ParedUsageTypesForSet(set) != nil);
          Check(ParedServiceInterface() != nil);
          NSDictionary *recovery = recoveries[i % recoveries.count];
          id native = Native(Subscription(recovery));
          NSError *error = nil;
          NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:native
                                                  requiringSecureCoding:YES
                                                                  error:&error];
          Check(archive && !error);
          id decoded = [NSKeyedUnarchiver
              unarchivedObjectOfClass:NSClassFromString(
                                          @"UAFAssetSetSubscription")
                             fromData:archive
                                error:&error];
          Check([decoded isEqual:native] && !error);
          for (NSString *alias in recovery[@"usageAliases"]) {
            Check(
                ParedResolveUsageAlias(alias, recovery[@"usageAliases"][alias])
                    .count > 0);
          }
          error = nil;
          ParedLocalDownloadStatus *status = ParedLocalStatus(set, &error);
          Check((status != nil) != (error != nil));
          id prior = baseline[set];
          if ([prior isKindOfClass:NSError.class]) {
            Check([error.domain isEqual:[prior domain]] &&
                  error.code == [prior code]);
          } else {
            ParedLocalDownloadStatus *expected = prior;
            Check(status &&
                  status.configuredAssetEntries ==
                      expected.configuredAssetEntries &&
                  status.downloadedAssets.count ==
                      expected.downloadedAssets.count);
          }
        }
      });
  unsigned int after = OpenFiles();
  printf("Live concurrent reads: 240, descriptors before/after: %u/%u\n",
         before, after);
  Check(after == before);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    Check(argc == 2);
    Check(dlopen("/System/Library/PrivateFrameworks/"
                 "UnifiedAssetFramework.framework/UnifiedAssetFramework",
                 RTLD_NOW));
    NSDictionary *catalog = [NSJSONSerialization
        JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])]
                   options:0
                     error:NULL];
    Check(catalog != nil);
    NSArray *recoveries = Recoveries(catalog);
    Check(recoveries.count > 0);
    MalformedInputs(recoveries[0]);
    for (NSDictionary *recovery in recoveries) {
      Ownership(recovery);
    }
    Wire(recoveries);
    WireFailure();
    StatusFaults();
    ValidationErrorFaults(recoveries[0]);
    ConfigurationFaults();
    InterfaceFaults();
    ABIFaults();
    ConcurrentReads(catalog, recoveries);
    printf("Private API checks passed: %u\n", atomic_load(&checks));
  }
  return 0;
}
