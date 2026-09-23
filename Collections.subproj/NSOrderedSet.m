/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <CoreFoundation/CFArray.h>

#include <stdarg.h>
#include <stdlib.h>

static CFComparisonResult NSOrderedSetDispatchComparator(const void *o1, const void *o2, void *context) {
    NSComparator cmptr = (__bridge NSComparator)context;
    return (CFComparisonResult)cmptr((__bridge id)o1, (__bridge id)o2);
}

static NSUInteger NSOrderedSetIndexOfObject(NSArray *array, id object) {
    NSUInteger count = [array count];
    for (NSUInteger i = 0; i < count; i++) {
        id candidate = [array objectAtIndex:i];
        if (candidate == object || [candidate isEqual:object]) {
            return i;
        }
    }
    return NSNotFound;
}

static NSMutableArray *NSOrderedSetCanonical(const id __unsafe_unretained *objects, NSUInteger count, BOOL copyItems) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        id object = objects[i];
        if (copyItems) {
            object = [(id)object copy];
        }
        if (![result containsObject:object]) {
            [result addObject:object];
        }
    }
    return result;
}

@interface NSMutableOrderedSet (PrivateSorting)
@end

@implementation NSOrderedSet {
}

- (NSUInteger)count {
    return [_osArray count];
}

- (id)objectAtIndex:(NSUInteger)index {
    return [_osArray objectAtIndex:index];
}

- (NSUInteger)indexOfObject:(id)object {
    return NSOrderedSetIndexOfObject(_osArray, object);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _osArray = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithObjects:(const id __unsafe_unretained *)objects count:(NSUInteger)count {
    self = [self init];
    if (self) {
        _osArray = NSOrderedSetCanonical(objects, count, NO);
    }
    return self;
}

- (instancetype)initWithObject:(id)object {
    id __unsafe_unretained buffer[1];
    buffer[0] = object;
    return [self initWithObjects:buffer count:1];
}

- (instancetype)initWithObjects:(id)firstObject, ... {
    if (!firstObject) {
        return [self init];
    }
    NSUInteger capacity = 0;
    va_list args;
    va_start(args, firstObject);
    while (va_arg(args, id)) {
        capacity++;
    }
    va_end(args);
    id __unsafe_unretained *objects = (id __unsafe_unretained *)calloc(capacity + 1, sizeof(*objects));
    if (!objects) {
        return nil;
    }
    va_start(args, firstObject);
    objects[0] = firstObject;
    for (NSUInteger i = 1; i <= capacity; i++) {
        objects[i] = va_arg(args, id);
    }
    va_end(args);
    NSMutableArray *ordered = NSOrderedSetCanonical(objects, capacity + 1, NO);
    free(objects);
    self = [self init];
    if (self) {
        _osArray = ordered;
    }
    return self;
}

- (instancetype)initWithArray:(NSArray *)array {
    return [self initWithArray:array range:NSMakeRange(0, [array count]) copyItems:NO];
}

- (instancetype)initWithArray:(NSArray *)array copyItems:(BOOL)copyItems {
    return [self initWithArray:array range:NSMakeRange(0, [array count]) copyItems:copyItems];
}

- (instancetype)initWithArray:(NSArray *)array range:(NSRange)range copyItems:(BOOL)copyItems {
    NSUInteger total = [array count];
    NSUInteger location = range.location > total ? total : range.location;
    NSUInteger length = range.length;
    if (location + length > total) {
        length = total - location;
    }
    id __unsafe_unretained *objects = length ? (id __unsafe_unretained *)calloc(length, sizeof(*objects)) : NULL;
    if (length && !objects) {
        return nil;
    }
    for (NSUInteger i = 0; i < length; i++) {
        objects[i] = [array objectAtIndex:location + i];
    }
    NSMutableArray *ordered = NSOrderedSetCanonical(objects, length, copyItems);
    free(objects);
    self = [self init];
    if (self) {
        _osArray = ordered;
    }
    return self;
}

- (instancetype)initWithOrderedSet:(NSOrderedSet *)set {
    return [self initWithArray:set->_osArray];
}

- (instancetype)initWithOrderedSet:(NSOrderedSet *)set copyItems:(BOOL)copyItems {
    return [self initWithArray:set->_osArray copyItems:copyItems];
}

- (instancetype)initWithOrderedSet:(NSOrderedSet *)set range:(NSRange)range copyItems:(BOOL)copyItems {
    return [self initWithArray:set->_osArray range:range copyItems:copyItems];
}

- (instancetype)initWithSet:(NSSet *)set {
    return [self initWithArray:[set allObjects]];
}

- (instancetype)initWithSet:(NSSet *)set copyItems:(BOOL)copyItems {
    return [self initWithArray:[set allObjects] copyItems:copyItems];
}

- (NSArray *)array {
    return _osArray;
}

- (NSSet *)set {
    return [NSSet setWithArray:_osArray];
}

- (id)firstObject {
    return [_osArray count] ? [_osArray objectAtIndex:0] : nil;
}

- (id)lastObject {
    return [_osArray count] ? [_osArray objectAtIndex:[_osArray count] - 1] : nil;
}

- (BOOL)isEqualToOrderedSet:(NSOrderedSet *)other {
    if (self == other) {
        return YES;
    }
    if (!other || [other count] != [self count]) {
        return NO;
    }
    for (NSUInteger i = 0; i < [self count]; i++) {
        id a = [_osArray objectAtIndex:i];
        id b = [other objectAtIndex:i];
        if (!(a == b || [a isEqual:b])) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[NSOrderedSet class]] ? [self isEqualToOrderedSet:object] : NO;
}

- (NSUInteger)hash {
    return [_osArray hash];
}

- (BOOL)containsObject:(id)object {
    return [_osArray containsObject:object];
}

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return [_osArray objectAtIndex:index];
}

- (NSEnumerator *)objectEnumerator {
    return [_osArray objectEnumerator];
}

- (NSEnumerator *)reverseObjectEnumerator {
    return [_osArray reverseObjectEnumerator];
}

- (NSOrderedSet *)reversedOrderedSet {
    NSArray *reversed = [[_osArray reverseObjectEnumerator] allObjects];
    return [[NSOrderedSet alloc] initWithArray:reversed];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    (void)zone;
    return [[NSMutableOrderedSet alloc] initWithArray:_osArray];
}

- (NSUInteger)indexOfObject:(id)object inSortedRange:(NSRange)range
                    options:(NSBinarySearchingOptions)options
             usingComparator:(NSComparator)cmptr {
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    NSUInteger low = location;
    NSUInteger high = location + length;
    while (low < high) {
        NSUInteger mid = low + (high - low) / 2;
        NSComparisonResult result = cmptr(object, [_osArray objectAtIndex:mid]);
        if (result == NSOrderedDescending) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (options & NSBinarySearchingInsertionIndex) {
        return low;
    }
    if (low < location + length && cmptr(object, [_osArray objectAtIndex:low]) == NSOrderedSame) {
        return low;
    }
    return NSNotFound;
}

- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr {
    NSMutableArray *copy = [_osArray mutableCopy];
    [copy sortUsingComparator:cmptr];
    return copy;
}

- (NSArray *)sortedArrayWithOptions:(NSSortOptions)options usingComparator:(NSComparator)cmptr {
    (void)options;
    NSMutableArray *copy = [_osArray mutableCopy];
    [copy sortUsingComparator:cmptr];
    return copy;
}

- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)sortDescriptors {
    NSMutableArray *copy = [_osArray mutableCopy];
    [copy sortUsingDescriptors:sortDescriptors];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_osArray forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSArray *decoded = [coder decodeObjectForKey:@"NS.objects"];
    return [self initWithArray:decoded];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained *)stackbuf count:(NSUInteger)len {
    NSUInteger count = [_osArray count];
    NSUInteger index = state->state;
    if (index == 0) {
        state->mutationsPtr = &state->extra[0];
        state->extra[0] = 0;
    }
    if (index >= count) {
        return 0;
    }
    NSUInteger batch = count - index;
    if (batch > len) {
        batch = len;
    }
    for (NSUInteger i = 0; i < batch; i++) {
        stackbuf[i] = [_osArray objectAtIndex:index + i];
    }
    state->itemsPtr = stackbuf;
    state->state = index + batch;
    return batch;
}

@end

@implementation NSOrderedSet (NSOrderedSetCreation)

+ (instancetype)orderedSet {
    return [[self alloc] init];
}

+ (instancetype)orderedSetWithObject:(id)object {
    return [[self alloc] initWithObject:object];
}

+ (instancetype)orderedSetWithObjects:(const id __unsafe_unretained *)objects count:(NSUInteger)count {
    return [[self alloc] initWithObjects:objects count:count];
}

+ (instancetype)orderedSetWithObjects:(id)firstObject, ... {
    va_list args;
    NSUInteger extra = 0;
    va_start(args, firstObject);
    while (va_arg(args, id)) {
        extra++;
    }
    va_end(args);
    NSUInteger total = firstObject ? extra + 1 : 0;
    id __unsafe_unretained *objects = total ? (id __unsafe_unretained *)calloc(total, sizeof(*objects)) : NULL;
    if (total && !objects) {
        return nil;
    }
    if (total) {
        va_start(args, firstObject);
        objects[0] = firstObject;
        for (NSUInteger i = 1; i < total; i++) {
            objects[i] = va_arg(args, id);
        }
        va_end(args);
    }
    NSOrderedSet *result = [[self alloc] initWithObjects:objects count:total];
    free(objects);
    return result;
}

+ (instancetype)orderedSetWithOrderedSet:(NSOrderedSet *)set {
    return [[self alloc] initWithOrderedSet:set];
}

+ (instancetype)orderedSetWithOrderedSet:(NSOrderedSet *)set range:(NSRange)range copyItems:(BOOL)copyItems {
    return [[self alloc] initWithOrderedSet:set range:range copyItems:copyItems];
}

+ (instancetype)orderedSetWithArray:(NSArray *)array {
    return [[self alloc] initWithArray:array];
}

+ (instancetype)orderedSetWithArray:(NSArray *)array range:(NSRange)range copyItems:(BOOL)copyItems {
    return [[self alloc] initWithArray:array range:range copyItems:copyItems];
}

+ (instancetype)orderedSetWithSet:(NSSet *)set {
    return [[self alloc] initWithSet:set];
}

+ (instancetype)orderedSetWithSet:(NSSet *)set copyItems:(BOOL)copyItems {
    return [[self alloc] initWithSet:set copyItems:copyItems];
}

@end

@implementation NSMutableOrderedSet {
}

+ (instancetype)orderedSetWithCapacity:(NSUInteger)capacity {
    return [[NSMutableOrderedSet alloc] initWithCapacity:capacity];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _osArray = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _osArray = [NSMutableArray arrayWithCapacity:capacity];
    }
    return self;
}

- (CFMutableArrayRef)_cfArray {
    return (__bridge CFMutableArrayRef)_osArray;
}

- (void)insertObject:(id)object atIndex:(NSUInteger)index {
    if ([_osArray containsObject:object]) {
        return;
    }
    CFArrayInsertValueAtIndex([self _cfArray], (CFIndex)index, (const void *)object);
}

- (void)removeObjectAtIndex:(NSUInteger)index {
    CFArrayRemoveValueAtIndex([self _cfArray], (CFIndex)index);
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)object {
    CFMutableArrayRef array = [self _cfArray];
    CFArrayRemoveValueAtIndex(array, (CFIndex)index);
    CFArrayInsertValueAtIndex(array, (CFIndex)index, (const void *)object);
}

- (void)addObject:(id)object {
    if (![_osArray containsObject:object]) {
        CFArrayAppendValue([self _cfArray], (const void *)object);
    }
}

- (void)addObjectsFromArray:(NSArray *)array {
    for (id object in array) {
        [self addObject:object];
    }
}

- (void)setObject:(id)object atIndex:(NSUInteger)index {
    if ([_osArray containsObject:object]) {
        return;
    }
    NSUInteger count = [_osArray count];
    if (index == count) {
        CFArrayAppendValue([self _cfArray], (const void *)object);
    } else if (index < count) {
        CFMutableArrayRef array = [self _cfArray];
        CFArrayRemoveValueAtIndex(array, (CFIndex)index);
        CFArrayInsertValueAtIndex(array, (CFIndex)index, (const void *)object);
    }
}

- (void)exchangeObjectAtIndex:(NSUInteger)index1 withObjectAtIndex:(NSUInteger)index2 {
    if (index1 == index2) {
        return;
    }
    CFArrayExchangeValuesAtIndices([self _cfArray], (CFIndex)index1, (CFIndex)index2);
}

- (void)removeAllObjects {
    CFArrayRemoveAllValues([self _cfArray]);
}

- (void)removeObject:(id)object {
    NSUInteger index = NSOrderedSetIndexOfObject(_osArray, object);
    if (index != NSNotFound) {
        [self removeObjectAtIndex:index];
    }
}

- (void)sortUsingComparator:(NSComparator)cmptr {
    [(NSMutableArray *)_osArray sortUsingComparator:cmptr];
}

- (void)sortWithOptions:(NSSortOptions)options usingComparator:(NSComparator)cmptr {
    (void)options;
    [(NSMutableArray *)_osArray sortUsingComparator:cmptr];
}

- (void)sortRange:(NSRange)range options:(NSSortOptions)options usingComparator:(NSComparator)cmptr {
    (void)options;
    CFMutableArrayRef array = [self _cfArray];
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    NSUInteger count = [_osArray count];
    if (location >= count) {
        return;
    }
    if (location + length > count) {
        length = count - location;
    }
    if (length < 2) {
        return;
    }
    const void **values = (const void **)calloc(length, sizeof(*values));
    if (!values) {
        return;
    }
    CFArrayGetValues(array, CFRangeMake((CFIndex)location, (CFIndex)length), values);
    CFMutableArrayRef slice = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    for (NSUInteger i = 0; i < length; i++) {
        CFArrayAppendValue(slice, values[i]);
    }
    CFArraySortValues(slice, CFRangeMake(0, (CFIndex)length), NSOrderedSetDispatchComparator, (void *)cmptr);
    free(values);
    for (NSUInteger i = 0; i < length; i++) {
        CFArrayRemoveValueAtIndex(array, (CFIndex)location);
    }
    for (NSUInteger i = 0; i < length; i++) {
        CFArrayInsertValueAtIndex(array, (CFIndex)(location + i), CFArrayGetValueAtIndex(slice, (CFIndex)i));
    }
    CFRelease(slice);
}

- (void)sortUsingDescriptors:(NSArray *)sortDescriptors {
    [(NSMutableArray *)_osArray sortUsingDescriptors:sortDescriptors];
}

@end