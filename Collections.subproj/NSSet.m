/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * The API and collection operations were adapted from Cocotron Foundation's
 * NSSet implementation by Christopher J. W. Lloyd and contributors, used
 * under its MIT license. The CF-backed storage here follows this tree's
 * NSArray and NSDictionary implementations instead of Cocotron's private
 * collection tables.
 */

#import <Foundation/NSSet.h>
#import <Foundation/NSNumber.h>
#include <CoreFoundation/CFSet.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <stdarg.h>

#if __has_feature(objc_arc)
#define NSSET_CF(type, value) ((__bridge type)(value))
#define NSSET_ID(type, value) ((__bridge_transfer type)(value))
#else
#define NSSET_CF(type, value) ((type)(value))
#define NSSET_ID(type, value) ((type)(value))
#endif

@interface _NSSetEnumerator : NSEnumerator {
    NSSet *_set;
    CFIndex _index;
    CFIndex _count;
    const void *_values[1];
}
- (instancetype)initWithSet:(NSSet *)set;
@end

static CFSetRef _NSSetCreateFromVarargs(id firstObject, va_list args) {
    NSUInteger capacity = 8;
    NSUInteger count = 0;
    const void **objects = (const void **)malloc(capacity * sizeof(*objects));
    if (objects == NULL) return NULL;
    id object = firstObject;
    while (object != nil) {
        if (count == capacity) {
            capacity *= 2;
            const void **grown = (const void **)realloc(objects, capacity * sizeof(*objects));
            if (grown == NULL) { free(objects); return NULL; }
            objects = grown;
        }
        objects[count++] = NSSET_CF(const void *, object);
        object = va_arg(args, id);
    }
    CFSetRef result = CFSetCreate(kCFAllocatorDefault, (const void **)objects,
                                  (CFIndex)count, &kCFTypeSetCallBacks);
    free(objects);
    return result;
}

static CFSetRef _NSSetCreateFromObjects(const __unsafe_unretained id *objects,
                                        NSUInteger count) {
    const void **values = count ? (const void **)malloc(count * sizeof(*values)) : NULL;
    if (count && values == NULL) return NULL;
    for (NSUInteger i = 0; i < count; i++) values[i] = NSSET_CF(const void *, objects[i]);
    CFSetRef result = CFSetCreate(kCFAllocatorDefault, values, (CFIndex)count,
                                  &kCFTypeSetCallBacks);
    free(values);
    return result;
}

static NSArray *_NSSetArray(NSSet *set) {
    CFIndex count = CFSetGetCount(NSSET_CF(CFSetRef, set));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count && values == NULL) return nil;
    if (count) CFSetGetValues(NSSET_CF(CFSetRef, set), values);
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, values, count,
                                     &kCFTypeArrayCallBacks);
    free(values);
    return NSSET_ID(NSArray *, array);
}

static void _NSSetAddValue(const void *value, void *context) {
    CFSetAddValue((CFMutableSetRef)context, value);
}

@implementation NSSet

+ (instancetype)set {
    return NSSET_ID(NSSet *, CFSetCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeSetCallBacks));
}

+ (instancetype)setWithObject:(id)object {
    const void *value = NSSET_CF(const void *, object);
    return NSSET_ID(NSSet *, CFSetCreate(kCFAllocatorDefault, &value, 1,
                                              &kCFTypeSetCallBacks));
}

+ (instancetype)setWithObjects:(const __unsafe_unretained id *)objects count:(NSUInteger)count {
    return NSSET_ID(NSSet *, _NSSetCreateFromObjects(objects, count));
}

+ (instancetype)setWithObjects:(id)firstObject, ... {
    if (firstObject == nil) return [self set];
    va_list args;
    va_start(args, firstObject);
    CFSetRef result = _NSSetCreateFromVarargs(firstObject, args);
    va_end(args);
    return NSSET_ID(NSSet *, result);
}

+ (instancetype)setWithSet:(NSSet *)set {
    return NSSET_ID(NSSet *, CFSetCreateCopy(kCFAllocatorDefault, NSSET_CF(CFSetRef, set)));
}

+ (instancetype)setWithArray:(NSArray *)array {
    id result = [[self alloc] initWithArray:array];
#if __has_feature(objc_arc)
    return result;
#else
    return [result autorelease];
#endif
}

- (instancetype)init {
    return NSSET_ID(NSSet *, CFSetCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeSetCallBacks));
}

- (instancetype)initWithObjects:(const __unsafe_unretained id *)objects count:(NSUInteger)count {
    return NSSET_ID(NSSet *, _NSSetCreateFromObjects(objects, count));
}

- (instancetype)initWithObjects:(id)firstObject, ... {
    if (firstObject == nil) return [self init];
    va_list args;
    va_start(args, firstObject);
    CFSetRef result = _NSSetCreateFromVarargs(firstObject, args);
    va_end(args);
    return NSSET_ID(NSSet *, result);
}

- (instancetype)initWithSet:(NSSet *)set {
    return NSSET_ID(NSSet *, CFSetCreateCopy(kCFAllocatorDefault, NSSET_CF(CFSetRef, set)));
}

- (instancetype)initWithSet:(NSSet *)set copyItems:(BOOL)copyItems {
    if (!copyItems) return [self initWithSet:set];
    CFIndex count = CFSetGetCount(NSSET_CF(CFSetRef, set));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count && values == NULL) return nil;
    if (count) CFSetGetValues(NSSET_CF(CFSetRef, set), values);
    for (CFIndex i = 0; i < count; i++) values[i] = NSSET_CF(const void *, [NSSET_ID(id, values[i]) copy]);
    CFSetRef result = CFSetCreate(kCFAllocatorDefault, values, count, &kCFTypeSetCallBacks);
#if !__has_feature(objc_arc)
    for (CFIndex i = 0; i < count; i++) [(id)values[i] release];
#endif
    free(values);
    return NSSET_ID(NSSet *, result);
}

- (instancetype)initWithArray:(NSArray *)array {
    CFIndex count = CFArrayGetCount(NSSET_CF(CFArrayRef, array));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count && values == NULL) return nil;
    if (count) CFArrayGetValues(NSSET_CF(CFArrayRef, array), CFRangeMake(0, count), values);
    CFSetRef result = CFSetCreate(kCFAllocatorDefault, values, count, &kCFTypeSetCallBacks);
    free(values);
    return NSSET_ID(NSSet *, result);
}

- (NSUInteger)count { return (NSUInteger)CFSetGetCount(NSSET_CF(CFSetRef, self)); }

- (id)member:(id)object { return (id)CFSetGetValue(NSSET_CF(CFSetRef, self), NSSET_CF(const void *, object)); }

- (BOOL)containsObject:(id)object { return CFSetContainsValue(NSSET_CF(CFSetRef, self), NSSET_CF(const void *, object)); }

- (id)anyObject {
    const void *value = NULL;
    CFSetGetValues(NSSET_CF(CFSetRef, self), &value);
    return NSSET_CF(id, value);
}

- (NSArray *)allObjects { return _NSSetArray(self); }

- (NSEnumerator *)objectEnumerator {
    return [[_NSSetEnumerator alloc] initWithSet:self];
}

- (BOOL)intersectsSet:(NSSet *)otherSet {
    CFIndex count = CFSetGetCount(NSSET_CF(CFSetRef, self));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count) CFSetGetValues(NSSET_CF(CFSetRef, self), values);
    BOOL result = NO;
    for (CFIndex i = 0; i < count && !result; i++) result = CFSetContainsValue(NSSET_CF(CFSetRef, otherSet), values[i]);
    free(values);
    return result;
}

- (BOOL)isEqualToSet:(NSSet *)otherSet {
    if (self == otherSet) return YES;
    if (otherSet == nil || self.count != otherSet.count) return NO;
    return [self isSubsetOfSet:otherSet];
}

- (BOOL)isSubsetOfSet:(NSSet *)otherSet {
    CFIndex count = CFSetGetCount(NSSET_CF(CFSetRef, self));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count) CFSetGetValues(NSSET_CF(CFSetRef, self), values);
    BOOL result = YES;
    for (CFIndex i = 0; i < count && result; i++) result = CFSetContainsValue(NSSET_CF(CFSetRef, otherSet), values[i]);
    free(values);
    return result;
}

- (NSSet *)setByAddingObject:(id)object {
    CFMutableSetRef result = CFSetCreateMutableCopy(kCFAllocatorDefault, 0, NSSET_CF(CFSetRef, self));
    if (result) CFSetAddValue(result, NSSET_CF(const void *, object));
    return NSSET_ID(NSSet *, result);
}

- (NSSet *)setByAddingObjectsFromSet:(NSSet *)set {
    CFMutableSetRef result = CFSetCreateMutableCopy(kCFAllocatorDefault, 0, NSSET_CF(CFSetRef, self));
    if (result) CFSetApplyFunction(NSSET_CF(CFSetRef, set), _NSSetAddValue, result);
    return NSSET_ID(NSSet *, result);
}

- (NSSet *)setByAddingObjectsFromArray:(NSArray *)array {
    NSMutableSet *result = [[NSMutableSet alloc] initWithSet:self];
    [result addObjectsFromArray:array];
    return result;
}

@end

@implementation NSMutableSet

+ (instancetype)setWithCapacity:(NSUInteger)capacity {
    return NSSET_ID(NSMutableSet *, CFSetCreateMutable(kCFAllocatorDefault, (CFIndex)capacity, &kCFTypeSetCallBacks));
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    return NSSET_ID(NSMutableSet *, CFSetCreateMutable(kCFAllocatorDefault, (CFIndex)capacity, &kCFTypeSetCallBacks));
}

- (instancetype)initWithSet:(NSSet *)set {
    return NSSET_ID(NSMutableSet *, CFSetCreateMutableCopy(kCFAllocatorDefault, 0,
                                                            NSSET_CF(CFSetRef, set)));
}

- (instancetype)initWithArray:(NSArray *)array {
    self = [self initWithCapacity:[array count]];
    if (self != nil) [self addObjectsFromArray:array];
    return self;
}

- (void)addObject:(id)object { CFSetAddValue(NSSET_CF(CFMutableSetRef, self), NSSET_CF(const void *, object)); }
- (void)removeObject:(id)object { CFSetRemoveValue(NSSET_CF(CFMutableSetRef, self), NSSET_CF(const void *, object)); }

- (void)addObjectsFromArray:(NSArray *)array {
    CFIndex count = CFArrayGetCount(NSSET_CF(CFArrayRef, array));
    for (CFIndex i = 0; i < count; i++) [self addObject:NSSET_CF(id, CFArrayGetValueAtIndex(NSSET_CF(CFArrayRef, array), i))];
}

- (void)intersectSet:(NSSet *)otherSet {
    CFIndex count = CFSetGetCount(NSSET_CF(CFSetRef, self));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count) CFSetGetValues(NSSET_CF(CFSetRef, self), values);
    for (CFIndex i = 0; i < count; i++) if (!CFSetContainsValue(NSSET_CF(CFSetRef, otherSet), values[i])) CFSetRemoveValue(NSSET_CF(CFMutableSetRef, self), values[i]);
    free(values);
}

- (void)minusSet:(NSSet *)otherSet {
    CFIndex count = CFSetGetCount(NSSET_CF(CFSetRef, otherSet));
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count) CFSetGetValues(NSSET_CF(CFSetRef, otherSet), values);
    for (CFIndex i = 0; i < count; i++) CFSetRemoveValue(NSSET_CF(CFMutableSetRef, self), values[i]);
    free(values);
}

- (void)removeAllObjects { CFSetRemoveAllValues(NSSET_CF(CFMutableSetRef, self)); }
- (void)unionSet:(NSSet *)otherSet { CFSetApplyFunction(NSSET_CF(CFSetRef, otherSet), _NSSetAddValue, NSSET_CF(void *, self)); }
- (void)setSet:(NSSet *)otherSet { CFSetRemoveAllValues(NSSET_CF(CFMutableSetRef, self)); [self unionSet:otherSet]; }

@end

@implementation _NSSetEnumerator

- (instancetype)initWithSet:(NSSet *)set {
    self = [super init];
    if (self) {
        _set = set;
        _count = CFSetGetCount(NSSET_CF(CFSetRef, set));
        _index = 0;
    }
    return self;
}

- (id)nextObject {
    if (_index >= _count) return nil;
    CFIndex count = _count;
    const void **values = (const void **)malloc((size_t)count * sizeof(*values));
    if (values == NULL) return nil;
    CFSetGetValues(NSSET_CF(CFSetRef, _set), values);
    id result = NSSET_CF(id, values[_index++]);
    free(values);
    return result;
}

@end

@implementation NSCountedSet

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    (void)capacity;
    _counts = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                         &kCFTypeDictionaryKeyCallBacks,
                                         &kCFTypeDictionaryValueCallBacks);
    return self;
}

- (instancetype)initWithArray:(NSArray *)array {
    self = [self initWithCapacity:[array count]];
    if (self != nil) [self addObjectsFromArray:array];
    return self;
}

- (instancetype)initWithSet:(NSSet *)set {
    self = [self initWithCapacity:[set count]];
    if (self != nil) {
        NSEnumerator *enumerator = [set objectEnumerator];
        id object;
        while ((object = [enumerator nextObject]) != nil) [self addObject:object];
    }
    return self;
}

- (NSUInteger)count { return (NSUInteger)CFDictionaryGetCount((CFDictionaryRef)_counts); }

- (NSUInteger)countForObject:(id)object {
    NSNumber *count = NSSET_CF(NSNumber *, CFDictionaryGetValue((CFDictionaryRef)_counts,
                                                                  NSSET_CF(const void *, object)));
    return count ? count.unsignedIntegerValue : 0;
}

- (id)member:(id)object {
    const void *key = CFDictionaryGetValue((CFDictionaryRef)_counts,
                                           NSSET_CF(const void *, object));
    return NSSET_CF(id, key);
}

- (BOOL)containsObject:(id)object { return [self countForObject:object] != 0; }

- (void)addObject:(id)object {
    NSUInteger count = [self countForObject:object];
    NSNumber *newCount = [NSNumber numberWithUnsignedInteger:count + 1];
    CFDictionarySetValue((CFMutableDictionaryRef)_counts,
                         NSSET_CF(const void *, object), NSSET_CF(const void *, newCount));
}

- (void)removeObject:(id)object {
    NSUInteger count = [self countForObject:object];
    if (count <= 1) {
        CFDictionaryRemoveValue((CFMutableDictionaryRef)_counts,
                                 NSSET_CF(const void *, object));
    } else {
        NSNumber *newCount = [NSNumber numberWithUnsignedInteger:count - 1];
        CFDictionarySetValue((CFMutableDictionaryRef)_counts,
                             NSSET_CF(const void *, object), NSSET_CF(const void *, newCount));
    }
}

- (void)removeAllObjects { CFDictionaryRemoveAllValues((CFMutableDictionaryRef)_counts); }

- (NSArray *)allObjects {
    CFIndex count = CFDictionaryGetCount((CFDictionaryRef)_counts);
    const void **keys = count ? (const void **)malloc((size_t)count * sizeof(*keys)) : NULL;
    const void **values = count ? (const void **)malloc((size_t)count * sizeof(*values)) : NULL;
    if (count) CFDictionaryGetKeysAndValues((CFDictionaryRef)_counts, keys, values);
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, keys, count, &kCFTypeArrayCallBacks);
    free(keys);
    free(values);
    return NSSET_ID(NSArray *, array);
}

- (NSEnumerator *)objectEnumerator { return [[self allObjects] objectEnumerator]; }

- (void)dealloc {
    if (_counts != NULL) CFRelease((CFTypeRef)_counts);
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFSetBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFSetGetTypeID(), "NSSet");
}
#endif
