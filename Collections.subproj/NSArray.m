/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSArray.h>
#import "NSEnumerator_array.h"
#import <Foundation/NSSortDescriptor.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <objc/message.h>
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

static CFComparisonResult NSNSArrayDispatchSelector(const void *object1, const void *object2,
                                                    void *context) {
    CFComparisonResult (*fn)(id, SEL, id) = (CFComparisonResult (*)(id, SEL, id))objc_msgSend;
    return fn((__bridge id)object1, (SEL)context, (__bridge id)object2);
}

static CFComparisonResult NSNSArrayDispatchComparator(const void *object1, const void *object2,
                                                      void *context) {
    NSComparator cmptr = (__bridge NSComparator)context;
    return (CFComparisonResult)cmptr((__bridge id)object1, (__bridge id)object2);
}

static CFComparisonResult NSNSArrayDispatchDescriptors(const void *object1, const void *object2,
                                                       void *context) {
    NSArray *descriptors = (__bridge NSArray *)context;
    for (NSSortDescriptor *descriptor in descriptors) {
        NSComparisonResult result = [descriptor compareObject:(__bridge id)object1
                                                     toObject:(__bridge id)object2];
        if (result != NSOrderedSame) {
            return (CFComparisonResult)result;
        }
    }
    return kCFCompareEqualTo;
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

- (instancetype)init {
    return NSARRAY_ID(CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks));
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

/* Fast enumeration streams straight out of the CF array: one item per slot of
 * the loop's stackbuf, the cursor kept in state->state (the runtime zeroes it
 * once per fresh loop and preserves it between chunk calls), and a stable
 * mutationsPtr that never changes so the loop can never be spurious-triggered.
 * A full chunk signals "more coming"; a short chunk or zero ends the loop. */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                 objects:(id __unsafe_unretained _Nullable[_Nonnull])stackbuf
                                   count:(NSUInteger)len {
    CFArrayRef array = NSARRAY_CF(CFArrayRef, self);
    CFIndex total = CFArrayGetCount(array);
    NSUInteger index = state->state;
    if (index >= (NSUInteger)total) {
        return 0;
    }
    state->mutationsPtr = &state->extra[0];
    state->itemsPtr = stackbuf;
    NSUInteger filled = 0;
    while (index < (NSUInteger)total && filled < len) {
        stackbuf[filled++] = NSARRAY_BORROWED(CFArrayGetValueAtIndex(array, (CFIndex)index));
        index++;
    }
    state->state = index;
    return filled;
}

- (NSArray *)sortedArrayUsingSelector:(SEL)comparator {
    if (comparator == NULL) {
        return [self copy];
    }
    CFMutableArrayRef sorted = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0,
                                                        NSARRAY_CF(CFArrayRef, self));
    CFArraySortValues(sorted, CFRangeMake(0, CFArrayGetCount(sorted)),
                      NSNSArrayDispatchSelector, (void *)comparator);
    return NSARRAY_ID(sorted);
}

- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr {
    CFMutableArrayRef sorted = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0,
                                                        NSARRAY_CF(CFArrayRef, self));
    CFArraySortValues(sorted, CFRangeMake(0, CFArrayGetCount(sorted)),
                      NSNSArrayDispatchComparator, (__bridge void *)cmptr);
    return NSARRAY_ID(sorted);
}

- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)sortDescriptors {
    CFMutableArrayRef sorted = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0,
                                                        NSARRAY_CF(CFArrayRef, self));
    CFArraySortValues(sorted, CFRangeMake(0, CFArrayGetCount(sorted)),
                      NSNSArrayDispatchDescriptors, (__bridge void *)sortDescriptors);
    return NSARRAY_ID(sorted);
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

+ (instancetype)arrayWithArray:(NSArray *)array {
    return NSARRAY_ID(CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, NSARRAY_CF(CFArrayRef, array)));
}

- (instancetype)init {
    return NSARRAY_ID(CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks));
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

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    CFArraySetValueAtIndex(NSARRAY_CF(CFMutableArrayRef, self), (CFIndex)index, NSARRAY_CF(const void *, anObject));
}

- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx {
    [self replaceObjectAtIndex:idx withObject:obj];
}

- (void)removeAllObjects {
    CFArrayRemoveAllValues(NSARRAY_CF(CFMutableArrayRef, self));
}

- (void)sortUsingSelector:(SEL)comparator {
    if (comparator == NULL) {
        return;
    }
    CFArraySortValues(NSARRAY_CF(CFMutableArrayRef, self),
                      CFRangeMake(0, CFArrayGetCount(NSARRAY_CF(CFArrayRef, self))),
                      NSNSArrayDispatchSelector, (void *)comparator);
}

- (void)sortUsingComparator:(NSComparator)cmptr {
    CFArraySortValues(NSARRAY_CF(CFMutableArrayRef, self),
                      CFRangeMake(0, CFArrayGetCount(NSARRAY_CF(CFArrayRef, self))),
                      NSNSArrayDispatchComparator, (__bridge void *)cmptr);
}

- (void)sortUsingDescriptors:(NSArray *)sortDescriptors {
    CFArraySortValues(NSARRAY_CF(CFMutableArrayRef, self),
                      CFRangeMake(0, CFArrayGetCount(NSARRAY_CF(CFArrayRef, self))),
                      NSNSArrayDispatchDescriptors, (__bridge void *)sortDescriptors);
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFArrayBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFArrayGetTypeID(), "NSArray");
}
#endif
