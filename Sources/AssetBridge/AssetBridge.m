#import "BridgeInternal.h"

#import <CoreFoundation/CoreFoundation.h>

#include <stdlib.h>

void ParedSetError(NSError **error, NSString *message) {
  if (error) {
    *error = [NSError errorWithDomain:@"org.pared"
                                 code:69
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
}

// The method signature cannot tell us whether the returned object is NSError
// Check its class before passing it to Swift
void ParedSetReturnedError(NSError **error, id returnedError) {
  if (![returnedError isKindOfClass:NSError.class]) {
    ParedSetError(error, @"Apple returned an unsupported error object");
  } else if (error) {
    *error = returnedError;
  }
}

// Compare return and argument types, including block and oneway qualifiers
// Ignore stack offsets, which vary without changing how the method is called
BOOL ParedSignatureMatches(const char *actual, const char *expected) {
  if (!actual || !expected) {
    return NO;
  }
  return [[NSMethodSignature signatureWithObjCTypes:actual]
      isEqual:[NSMethodSignature signatureWithObjCTypes:expected]];
}

// Compare against the compiler's encoding of the protocol declaration so this
// check stays in sync with the types used at the call site
BOOL ParedMethodMatches(Method method, SEL selector, Protocol *contract,
                        BOOL instance) {
  struct objc_method_description expected =
      protocol_getMethodDescription(contract, selector, YES, instance);
  return method &&
         ParedSignatureMatches(method_getTypeEncoding(method), expected.types);
}

BOOL ParedHasMethod(id object, SEL selector, Protocol *contract) {
  Method method = class_getInstanceMethod(object_getClass(object), selector);
  return ParedMethodMatches(method, selector, contract,
                            !object_isClass(object));
}

// The runtime lists only this protocol's own declarations; check inherited
// protocols separately when they are part of the native call surface
static BOOL ParedDeclaredMethodsMatch(Class receiver, Protocol *contract,
                                      BOOL instance) {
  unsigned int count = 0;
  struct objc_method_description *methods =
      protocol_copyMethodDescriptionList(contract, YES, instance, &count);
  BOOL supported = receiver && count > 0;
  for (unsigned int i = 0; supported && i < count; i++) {
    Method method = class_getInstanceMethod(receiver, methods[i].name);
    supported = method && ParedSignatureMatches(method_getTypeEncoding(method),
                                                methods[i].types);
  }
  free(methods);
  return supported;
}

BOOL ParedHasDeclaredMethods(id object, Protocol *contract) {
  return ParedDeclaredMethodsMatch(object_getClass(object), contract,
                                   !object_isClass(object));
}

BOOL ParedInstancesHaveDeclaredMethods(Class type, Protocol *contract) {
  return ParedDeclaredMethodsMatch(type, contract, YES);
}

BOOL ParedNonemptyString(id value) {
  return [value isKindOfClass:NSString.class] && [value length] != 0;
}

BOOL ParedHasNonemptyStrings(id values) {
  if (![values isKindOfClass:NSArray.class]) {
    return NO;
  }
  for (id value in values) {
    if (!ParedNonemptyString(value)) {
      return NO;
    }
  }
  return YES;
}

static BOOL ParedHasStringValues(id values) {
  if (![values isKindOfClass:NSDictionary.class]) {
    return NO;
  }
  for (id key in values) {
    if (![key isKindOfClass:NSString.class] ||
        ![values[key] isKindOfClass:NSString.class]) {
      return NO;
    }
  }
  return YES;
}

ParedStringValues *ParedCopyStringValues(id values) {
  return ParedHasStringValues(values)
             ? [[NSDictionary alloc] initWithDictionary:values copyItems:YES]
             : nil;
}

ParedAssetSetUsages *ParedCopyAssetSetUsages(id sets) {
  if (![sets isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  for (id name in sets) {
    if (![name isKindOfClass:NSString.class] ||
        !ParedHasStringValues(sets[name])) {
      return nil;
    }
  }
  // copyItems:YES stops after one level; Apple retains nested usage maps, so
  // recursively freeze their strings and containers before validation and XPC
  return CFBridgingRelease(CFPropertyListCreateDeepCopy(
      kCFAllocatorDefault, (__bridge CFPropertyListRef)sets,
      kCFPropertyListImmutable));
}
