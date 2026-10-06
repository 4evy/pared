#import "BridgeInternal.h"

#import "SubscriptionInternal.h"

NSXPCInterface *ParedServiceInterface(void) {
  Class type = NSClassFromString(@"UAFXPCProxyServiceInterface");
  if (!ParedHasMethod(type, @selector(defaultInterface),
                      @protocol(ParedServiceInterfaceAPI))) {
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
  struct objc_method_description expected = protocol_getMethodDescription(
      @protocol(ParedServiceAPI), operation, YES, YES);
  if (!ParedSignatureMatches(method.types, expected.types)) {
    return nil;
  }
  // Keep Apple's interface: a Swift protocol alone cannot describe the allowed
  // classes inside a subscription
  NSSet<Class> *request = [interface classesForSelector:operation
                                          argumentIndex:0
                                                ofReply:NO];
  Class subscription = NSClassFromString(@"UAFAssetSetSubscription");
  if (!subscription) {
    return nil;
  }
  NSSet<Class> *required = [NSSet setWithArray:@[
    subscription, NSString.class, NSDictionary.class, NSArray.class,
    NSNumber.class
  ]];
  if (![required isSubsetOfSet:request] ||
      ![[interface classesForSelector:operation argumentIndex:0
                              ofReply:YES] containsObject:NSError.class]) {
    return nil;
  }
  return interface;
}

// Copy names before XPC can defer serialization, so caller mutations cannot
// change the request. Remove duplicates to avoid resetting a set twice
static NSArray<NSString *> *ParedCopyNames(NSArray<NSString *> *values) {
  if (!ParedHasNonemptyStrings(values)) {
    return nil;
  }
  NSArray<NSString *> *snapshot = [[NSArray alloc] initWithArray:values
                                                       copyItems:YES];
  return [[[NSSet setWithArray:snapshot] allObjects]
      sortedArrayUsingSelector:@selector(compare:)];
}

static BOOL ParedSendConfiguration(NSObject *proxy,
                                   NSDictionary<NSString *, id> *configuration,
                                   void (^completion)(NSError *),
                                   NSError **error) {
  if (!proxy || !completion) {
    ParedSetError(
        error, @"A request requires a proxy and completion; no request sent");
    return NO;
  }
  // XPC proxies forward this method, so it will not appear in their class's
  // method list. Check the interface when setting up the connection instead
  [(id<ParedServiceAPI>)proxy operationWithConfig:configuration
                                       completion:completion];
  return YES;
}

// Reset affects these asset sets for all users and leaves subscriptions intact
// The daemon continues after individual errors and may force removal without
// waiting for existing locks. Some failures are only logged, so a successful
// reply does not prove every payload was deleted
BOOL ParedPerformReset(NSObject *proxy, NSArray<NSString *> *assetSets,
                       void (^completion)(NSError *_Nullable),
                       NSError **error) {
  // Omitting AssetSets resets every set; require explicit nonempty names
  assetSets = ParedCopyNames(assetSets);
  if (assetSets.count == 0) {
    ParedSetError(
        error,
        @"Reset requires explicit nonempty asset set names; no request sent");
    return NO;
  }
  return ParedSendConfiguration(
      proxy, @{@"Operation" : @"ResetAssetSets", @"AssetSets" : assetSets},
      completion, error);
}

// The daemon uses the connection's effective user; a system connection uses
// the console user and can fail if nobody is logged in
//
// Identical subscriptions are skipped. Changed requests still may not trigger
// a download if other subscribers already request the same assets
//
// Explicit usages and alias expansions stay separate alternatives for each
// set. The daemon resolves aliases again, so their contents can change between
// our validation and request processing
//
// Asset configuration happens before the database write. It can survive a
// failed write, and some download errors are only logged
BOOL ParedPerformSubscribe(NSObject *proxy, NSString *subscriber,
                           NSArray<ParedAssetSubscription *> *subscriptions,
                           void (^completion)(NSError *_Nullable),
                           NSError **error) {
  if (!ParedNonemptyString(subscriber) ||
      ![subscriptions isKindOfClass:NSArray.class] ||
      subscriptions.count == 0) {
    ParedSetError(error, @"Subscribe requires a subscriber and validated "
                         @"subscriptions; no request sent");
    return NO;
  }
  NSMutableArray<id<ParedSubscriptionAPI>> *native =
      [NSMutableArray arrayWithCapacity:subscriptions.count];
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (ParedAssetSubscription *subscription in subscriptions) {
    if (![subscription isKindOfClass:ParedAssetSubscription.class] ||
        !subscription.native) {
      ParedSetError(error, @"Unknown subscription wrapper; no request sent");
      return NO;
    }
    // The daemon keys subscriptions by name and does not preserve request order
    // Reject duplicates rather than let it choose between conflicting entries
    if ([names containsObject:subscription.name]) {
      ParedSetError(error, @"Duplicate subscription name; no request sent");
      return NO;
    }
    [names addObject:subscription.name];
    [native addObject:subscription.native];
  }
  return ParedSendConfiguration(
      proxy, @{
        @"Operation" : @"Subscribe",
        @"Subscriber" : [subscriber copy],
        @"Subscriptions" : [native copy],
        @"UserInitiated" : @YES
      },
      completion, error);
}

// Only this user's subscriber/name pairs are removed; other subscribers can
// keep the same assets requested. Delivery changes happen before the database
// write and can survive an error
//
// Unreadable stored requests can be skipped as though absent, so success does
// not prove a corrupt request was deleted
BOOL ParedPerformUnsubscribe(NSObject *proxy, NSString *subscriber,
                             NSArray<NSString *> *names,
                             void (^completion)(NSError *_Nullable),
                             NSError **error) {
  names = ParedCopyNames(names);
  if (!ParedNonemptyString(subscriber) || names.count == 0) {
    ParedSetError(error, @"Unsubscribe requires a subscriber and subscription "
                         @"names; no request sent");
    return NO;
  }
  return ParedSendConfiguration(
      proxy, @{
        @"Operation" : @"Unsubscribe",
        @"Subscriber" : [subscriber copy],
        @"Subscriptions" : names,
        @"UserInitiated" : @YES
      },
      completion, error);
}
