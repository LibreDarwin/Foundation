/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSArray.h>
#import "NSEnumerator_array.h"
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <objc/runtime.h>
#include <stdlib.h>

#if __has_feature(objc_arc)
#define NSARRAY_ID(value) ((__bridge_transfer id)(value))
#define NSARRAY_BORROWED(value) ((__bridge id)(value))
#define NSARRAY_CF(type, value) ((__bridge type)(value))
#else
#define NSARRAY_ID(value) ((id)(value))
#define NSARRAY_BORROWED(value) ((id)(value))
#define NSARRAY_CF(type, value) ((type)(value))
#endif

static CFArrayRef NSNSArrayCreate(const id *objects, NSUInteger count) {
    const void **values = count == 0 ? NULL : malloc(count * sizeof(*values));
    if (count != 0 && values == NULL) return NULL;
    for (NSUInteger index = 0; index < count; index++) {
        values[index] = NSARRAY_CF(const void *, objects[index]);
    }
    CFArrayRef result = CFArrayCreate(kCFAllocatorDefault, values, (CFIndex)count,
                                      &kCFTypeArrayCallBacks);
    free(values);
    return result;
}

@implementation NSArray

+ (instancetype)array {
    return NSARRAY_ID(CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks));
}

+ (instancetype)arrayWithObjects:(const id *)objects count:(NSUInteger)count {
    return NSARRAY_ID(NSNSArrayCreate(objects, count));
}

+ (instancetype)arrayWithArray:(NSArray *)array {
    return NSARRAY_ID(CFArrayCreateCopy(kCFAllocatorDefault, NSARRAY_CF(CFArrayRef, array)));
}

- (NSUInteger)count {
    return (NSUInteger)CFArrayGetCount(NSARRAY_CF(CFArrayRef, self));
}

- (id)objectAtIndex:(NSUInteger)index {
    return NSARRAY_BORROWED(CFArrayGetValueAtIndex(NSARRAY_CF(CFArrayRef, self), (CFIndex)index));
}

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return [self objectAtIndex:index];
}

- (BOOL)containsObject:(id)object {
    CFArrayRef array = NSARRAY_CF(CFArrayRef, self);
    CFIndex n = CFArrayGetCount(array);
    return CFArrayContainsValue(array, CFRangeMake(0, n),
                                NSARRAY_CF(const void *, object)) ? YES : NO;
}

- (BOOL)isEqualToArray:(NSArray *)array {
    return array != nil && CFEqual(NSARRAY_CF(CFTypeRef, self), NSARRAY_CF(CFTypeRef, array));
}

- (NSUInteger)hash {
    return (NSUInteger)CFHash(NSARRAY_CF(CFTypeRef, self));
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return NSARRAY_ID(CFArrayCreateCopy(kCFAllocatorDefault, NSARRAY_CF(CFArrayRef, self)));
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    (void)zone;
    return NSARRAY_ID(CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, NSARRAY_CF(CFArrayRef, self)));
}

- (NSEnumerator *)objectEnumerator {
    return [[NSEnumerator_array alloc] initWithArray:self];
}

- (NSEnumerator *)reverseObjectEnumerator {
    return [[NSEnumerator_arrayReverse alloc] initWithArray:self];
}

@end

@implementation NSMutableArray

+ (instancetype)arrayWithCapacity:(NSUInteger)capacity {
    return NSARRAY_ID(CFArrayCreateMutable(kCFAllocatorDefault, (CFIndex)capacity,
                                            &kCFTypeArrayCallBacks));
}

+ (instancetype)array {
    return [self arrayWithCapacity:0];
}

- (void)addObject:(id)object {
    CFArrayAppendValue(NSARRAY_CF(CFMutableArrayRef, self), NSARRAY_CF(const void *, object));
}

- (void)addObjectsFromArray:(NSArray *)array {
    CFArrayRef source = NSARRAY_CF(CFArrayRef, array);
    CFIndex n = CFArrayGetCount(source);
    CFArrayAppendArray(NSARRAY_CF(CFMutableArrayRef, self), source,
                       CFRangeMake(0, n));
}

- (void)removeObjectAtIndex:(NSUInteger)index {
    CFArrayRemoveValueAtIndex(NSARRAY_CF(CFMutableArrayRef, self), (CFIndex)index);
}

- (void)removeAllObjects {
    CFArrayRemoveAllValues(NSARRAY_CF(CFMutableArrayRef, self));
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFArrayBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFArrayGetTypeID(), "NSArray");
}
#endif
