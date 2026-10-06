#pragma once

#import "AssetBridge.h"
#import "PrivateAPI.h"

#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

void ParedSetError(NSError *_Nullable *_Nullable error, NSString *message);
void ParedSetReturnedError(NSError *_Nullable *_Nullable error,
                           id _Nullable returnedError);
BOOL ParedSignatureMatches(const char *_Nullable actual,
                           const char *_Nullable expected);
BOOL ParedMethodMatches(Method _Nullable method, SEL selector,
                        Protocol *contract, BOOL instance);
BOOL ParedHasMethod(id _Nullable object, SEL selector, Protocol *contract);
// Checks the protocol's own required declarations without requiring conformance
BOOL ParedHasDeclaredMethods(id _Nullable object, Protocol *contract);
BOOL ParedInstancesHaveDeclaredMethods(Class _Nullable type,
                                       Protocol *contract);
BOOL ParedNonemptyString(id _Nullable value);
BOOL ParedHasNonemptyStrings(id _Nullable values);
ParedStringValues *_Nullable ParedCopyStringValues(id _Nullable values);
ParedAssetSetUsages *_Nullable ParedCopyAssetSetUsages(id _Nullable sets);

NS_ASSUME_NONNULL_END
