#pragma once

#import "AssetBridge.h"
#import "PrivateAPI.h"

NS_ASSUME_NONNULL_BEGIN

// Keep the native object inside the bridge; only the request builder needs it
@interface ParedAssetSubscription ()
@property(nonatomic, readonly, strong) id<ParedSubscriptionAPI> native;
@property(nonatomic, readonly, copy) NSString *name;
- (instancetype)initWithNative:(id<ParedSubscriptionAPI>)native
                          name:(NSString *)name NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
