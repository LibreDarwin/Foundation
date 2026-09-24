/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This port twin of Apple's NSHashTable.m implements an open-addressed
 * bucket store whose insert/remove/member machinery mirrors the port's
 * NSMapTable.m byte-for-byte, specialized for set (single-pointer)
 * semantics described by an NSPointerFunctions personality.
 *
 * Compiled with -fno-objc-arc (MRC) to match NSMapTable.m.
 */

#import "NSHashTable.h"
#import "NSPointerFunctions.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSCoder.h>
#import <CoreFoundation/CFString.h>
#import <stdlib.h>
#import <string.h>

#if !defined(__FOUNDATION_NSHASHTABLE_IMPL__)
#define __FOUNDATION_NSHASHTABLE_IMPL__ 1

@interface NSHashTable (Internal)
- (instancetype)_initLegacyWithCallbacks:(NSHashTableCallBacks)callBacks capacity:(NSUInteger)capacity;
- (NSUInteger)_hashForItem:(const void *)item;
- (BOOL)_isItem:(const void *)item equalToItem:(const void *)other;
@end

@interface NSPointerFunctions (NSHashTableInternal)
- (NSPointerFunctionsOptions)_options;
@end

/* Bucket states.  Identical to the twin store in NSMapTable.m. */
typedef NS_ENUM(NSUInteger, NSHashBucketState) {
    NSHashBucketEmpty = 0,
    NSHashBucketOccupied,
    NSHashBucketDeleted,
};

typedef struct {
    NSHashBucketState _state;
    const void * _Nullable _item;
} NSHashBucket;

static const NSUInteger NSHashTableInitialBucketCount = 8;

/* Shifted-pointer hash used for Opaque/ObjectPointer personalities. */
static NSUInteger NSHashShiftedPointerHash(register const void *item) {
    register NSUInteger pointer = (NSUInteger)item;
    pointer >>= 4;
    pointer <<= 4;
    return pointer;
}

@implementation NSHashTable {
@public
    NSHashBucket *_buckets;
    NSUInteger _bucketCount;
    NSUInteger _occupiedCount;
    NSPointerFunctions *_pointerFunctions;
    BOOL _copyIn;
    BOOL _weakMemory;
    unsigned long _mutations;
    NSHashTableCallBacks _legacyCallbacks;
    BOOL _usesLegacyCallbacks;
}

+ (NSHashTable *)hashTableWithOptions:(NSPointerFunctionsOptions)options {
    return [[self alloc] initWithOptions:options capacity:0];
}

+ (NSHashTable *)hashTableWithWeakObjects {
    return [self hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality];
}

+ (NSHashTable *)weakObjectsHashTable {
    return [self hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality];
}

- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options capacity:(NSUInteger)capacity {
    self = [self initWithPointerFunctions:[NSPointerFunctions pointerFunctionsWithOptions:options] capacity:capacity];
    if (self) {
        _copyIn = (options & NSPointerFunctionsCopyIn) ? YES : NO;
        _weakMemory = ((options & 0x07) == NSPointerFunctionsWeakMemory) ? YES : NO;
    }
    return self;
}

- (instancetype)initWithPointerFunctions:(NSPointerFunctions *)functions capacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _pointerFunctions = [functions copy];
        _copyIn = NO;
        _weakMemory = NO;
        _bucketCount = NSHashTableInitialBucketCount;
        while (_bucketCount < capacity * 2) {
            _bucketCount *= 2;
        }
        _buckets = calloc(_bucketCount, sizeof(NSHashBucket));
        if (!_buckets) {
            return nil;
        }
    }
    return self;
}

- (instancetype)_initLegacyWithCallbacks:(NSHashTableCallBacks)callBacks capacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _legacyCallbacks = callBacks;
        _usesLegacyCallbacks = YES;
        _pointerFunctions = nil;
        _copyIn = NO;
        _weakMemory = NO;
        _bucketCount = NSHashTableInitialBucketCount;
        while (_bucketCount < capacity * 2) {
            _bucketCount *= 2;
        }
        _buckets = calloc(_bucketCount, sizeof(NSHashBucket));
        if (!_buckets) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [self removeAllObjects];
    [_pointerFunctions release];
    free(_buckets);
    [super dealloc];
}

- (NSPointerFunctions *)pointerFunctions {
    return [_pointerFunctions copy];
}

- (NSUInteger)count {
    return _occupiedCount;
}

- (NSUInteger)_indexForItem:(const void *)item {
    NSUInteger mask = _bucketCount - 1;
    NSUInteger index = [self _hashForItem:item] & mask;
    return index;
}

- (NSUInteger)_hashForItem:(const void *)item {
    if (_usesLegacyCallbacks) {
        if (_legacyCallbacks.hash != NULL) {
            return _legacyCallbacks.hash(self, item);
        }
        return (NSUInteger)(uintptr_t)item;
    }
    NSUInteger (*hashFunction)(const void *, NSUInteger (*)(const void *)) = _pointerFunctions.hashFunction;
    if (hashFunction) {
        return hashFunction(item, NULL);
    }
    return NSHashShiftedPointerHash(item);
}

- (BOOL)_isItem:(const void *)item equalToItem:(const void *)other {
    if (_usesLegacyCallbacks) {
        if (_legacyCallbacks.isEqual != NULL) {
            return _legacyCallbacks.isEqual(self, item, other);
        }
        return (item == other);
    }
    BOOL (*isEqualFunction)(const void *, const void *, NSUInteger (*)(const void *)) = _pointerFunctions.isEqualFunction;
    if (isEqualFunction) {
        return isEqualFunction(item, other, NULL);
    }
    return (item == other);
}

- (void)addObject:(id)object {
    const void *item = (__bridge const void *)object;
    if (_copyIn) {
        void *(*acquireFunction)(const void *, NSUInteger (*)(const void *), BOOL) = _pointerFunctions.acquireFunction;
        if (acquireFunction) {
            item = acquireFunction(item, _pointerFunctions.sizeFunction, YES);
        }
    }
    if (((_occupiedCount + 1) * 4) >= (_bucketCount * 3)) {
        [self _resize:_bucketCount * 2];
    }
    NSUInteger mask = _bucketCount - 1;
    NSUInteger index = [self _indexForItem:item];
    for (;;) {
        NSHashBucket *bucket = &_buckets[index];
        if (bucket->_state == NSHashBucketOccupied && [self _isItem:item equalToItem:bucket->_item]) {
            return;  /* already present; set semantics */
        }
        if (bucket->_state != NSHashBucketOccupied) {
            if (_usesLegacyCallbacks && _legacyCallbacks.retain != NULL) {
                _legacyCallbacks.retain(self, item);
            }
            bucket->_state = NSHashBucketOccupied;
            bucket->_item = item;
            _occupiedCount++;
            _mutations++;
            return;
        }
        index = (index + 1) & mask;
    }
}

- (void)removeObject:(id)object {
    const void *item = (__bridge const void *)object;
    NSUInteger mask = _bucketCount - 1;
    NSUInteger index = [self _indexForItem:item];
    for (;;) {
        NSHashBucket *bucket = &_buckets[index];
        if (bucket->_state == NSHashBucketEmpty) {
            return;  /* not present */
        }
        if (bucket->_state == NSHashBucketOccupied && [self _isItem:item equalToItem:bucket->_item]) {
            [self _removeBucketAtIndex:index];
            return;
        }
        index = (index + 1) & mask;
    }
}

- (void)removeAllObjects {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied) {
            [self _relinquishItem:_buckets[i]._item];
        }
        _buckets[i]._state = NSHashBucketEmpty;
        _buckets[i]._item = NULL;
    }
    _occupiedCount = 0;
    _mutations++;
}

- (id)member:(id)object {
    const void *item = (__bridge const void *)object;
    NSUInteger mask = _bucketCount - 1;
    NSUInteger index = [self _indexForItem:item];
    for (;;) {
        NSHashBucket *bucket = &_buckets[index];
        if (bucket->_state == NSHashBucketEmpty) {
            return nil;
        }
        if (bucket->_state == NSHashBucketOccupied && [self _isItem:item equalToItem:bucket->_item]) {
            return (__bridge id)bucket->_item;
        }
        index = (index + 1) & mask;
    }
}

- (BOOL)containsObject:(id)anObject {
    return ([self member:anObject] != nil);
}

- (NSEnumerator *)objectEnumerator {
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:_occupiedCount];
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied) {
            [objects addObject:(__bridge id)_buckets[i]._item];
        }
    }
    return [objects objectEnumerator];
}

- (NSArray *)allObjects {
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:_occupiedCount];
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied) {
            [objects addObject:(__bridge id)_buckets[i]._item];
        }
    }
    return objects;
}

- (void)_rehashIntoBuckets:(NSHashBucket *)buckets count:(NSUInteger)count {
    NSUInteger mask = count - 1;
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state != NSHashBucketOccupied) {
            continue;
        }
        const void *item = _buckets[i]._item;
        NSUInteger index = [self _hashForItem:item] & mask;
        while (buckets[index]._state == NSHashBucketOccupied) {
            index = (index + 1) & mask;
        }
        buckets[index]._state = NSHashBucketOccupied;
        buckets[index]._item = item;
    }
}

- (void)_resize:(NSUInteger)newCount {
    NSHashBucket *newBuckets = calloc(newCount, sizeof(NSHashBucket));
    if (!newBuckets) {
        return;
    }
    [self _rehashIntoBuckets:newBuckets count:newCount];
    free(_buckets);
    _buckets = newBuckets;
    _bucketCount = newCount;
}

- (void)_relinquishItem:(const void *)item {
    if (_usesLegacyCallbacks) {
        if (_legacyCallbacks.release != NULL) {
            _legacyCallbacks.release(self, (void *)item);
        }
        return;
    }
    void (*relinquishFunction)(const void *, NSUInteger (*)(const void *)) = _pointerFunctions.relinquishFunction;
    if (relinquishFunction) {
        relinquishFunction(item, _pointerFunctions.sizeFunction);
    }
}

- (void)_removeBucketAtIndex:(NSUInteger)index {
    NSHashBucket *bucket = &_buckets[index];
    [self _relinquishItem:bucket->_item];
    bucket->_state = NSHashBucketDeleted;
    bucket->_item = NULL;
    _occupiedCount--;
    _mutations++;
}

- (void)intersectHashTable:(NSHashTable *)other {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied &&
            ![other containsObject:(__bridge id)_buckets[i]._item]) {
            [self _removeBucketAtIndex:i];
        }
    }
}

- (void)unionHashTable:(NSHashTable *)other {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (other->_buckets[i]._state == NSHashBucketOccupied) {
            [self addObject:(__bridge id)other->_buckets[i]._item];
        }
    }
}

- (void)minusHashTable:(NSHashTable *)other {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied &&
            [other containsObject:(__bridge id)_buckets[i]._item]) {
            [self _removeBucketAtIndex:i];
        }
    }
}

- (BOOL)intersectsHashTable:(NSHashTable *)other {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied &&
            [other containsObject:(__bridge id)_buckets[i]._item]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isEqualToHashTable:(NSHashTable *)other {
    if (_occupiedCount != other->_occupiedCount) {
        return NO;
    }
    return [self isSubsetOfHashTable:other];
}

- (BOOL)isSubsetOfHashTable:(NSHashTable *)other {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied &&
            ![other containsObject:(__bridge id)_buckets[i]._item]) {
            return NO;
        }
    }
    return YES;
}

- (id)anyObject {
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied) {
            return (__bridge id)_buckets[i]._item;
        }
    }
    return nil;
}

- (NSSet *)setRepresentation {
    return [NSSet setWithArray:[self allObjects]];
}

- (id)copyWithZone:(NSZone *)zone {
    NSHashTable *copy;
    if (_usesLegacyCallbacks) {
        copy = [[NSHashTable alloc] _initLegacyWithCallbacks:_legacyCallbacks capacity:_occupiedCount];
    } else {
        copy = [[NSHashTable alloc] initWithOptions:[_pointerFunctions _options] capacity:_occupiedCount];
    }
    for (NSUInteger i = 0; i < _bucketCount; i++) {
        if (_buckets[i]._state == NSHashBucketOccupied) {
            [copy addObject:(__bridge id)_buckets[i]._item];
        }
    }
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:(NSInteger)[_pointerFunctions _options] forKey:@"NS.options"];
    [coder encodeObject:[self allObjects] forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSPointerFunctionsOptions options = (NSPointerFunctionsOptions)[coder decodeIntegerForKey:@"NS.options"];
    self = [self initWithOptions:options capacity:0];
    if (self) {
        NSArray *objects = [coder decodeObjectForKey:@"NS.objects"];
        for (id object in objects) {
            [self addObject:object];
        }
    }
    return self;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                 objects:(id __unsafe_unretained _Nullable[_Nonnull])buffer
                                   count:(NSUInteger)len {
    NSUInteger index = state->state;
    if (index >= _bucketCount) {
        return 0;
    }
    state->itemsPtr = buffer;
    state->mutationsPtr = &_mutations;
    NSUInteger outCount = 0;
    while (index < _bucketCount && outCount < len) {
        if (_buckets[index]._state == NSHashBucketOccupied) {
            buffer[outCount++] = (__bridge id)_buckets[index]._item;
        }
        index++;
    }
    state->state = index;
    return outCount;
}

@end

/****************	(void *) Hash table operations	****************/

void NSFreeHashTable(NSHashTable *table) {
    [table release];
}

void NSResetHashTable(NSHashTable *table) {
    [table removeAllObjects];
}

BOOL NSCompareHashTables(NSHashTable *table1, NSHashTable *table2) {
    return [table1 isEqualToHashTable:table2];
}

NSHashTable *NSCopyHashTableWithZone(NSHashTable *table, NSZone *zone) {
    if (table == NULL) {
        return NULL;
    }
    return [[table copyWithZone:zone] autorelease];
}

void *NSHashGet(NSHashTable *table, const void *pointer) {
    return (void *)[table member:(__bridge id)pointer];
}

void NSHashInsert(NSHashTable *table, const void *pointer) {
    [table addObject:(__bridge id)pointer];
}

void NSHashInsertKnownAbsent(NSHashTable *table, const void *pointer) {
    [table addObject:(__bridge id)pointer];
}

void *NSHashInsertIfAbsent(NSHashTable *table, const void *pointer) {
    void *existing = (void *)[table member:(__bridge id)pointer];
    if (!existing) {
        [table addObject:(__bridge id)pointer];
    }
    return existing;
}

void NSHashRemove(NSHashTable *table, const void *pointer) {
    [table removeObject:(__bridge id)pointer];
}

NSHashEnumerator NSEnumerateHashTable(NSHashTable *table) {
    NSHashEnumerator enumerator;
    enumerator._pi = 0;
    enumerator._si = table->_bucketCount;
    enumerator._bs = table->_buckets;
    return enumerator;
}

void *NSNextHashEnumeratorItem(NSHashEnumerator *enumerator) {
    NSHashBucket *buckets = (NSHashBucket *)enumerator->_bs;
    NSUInteger limit = enumerator->_si;
    while (enumerator->_pi < limit) {
        NSHashBucket *bucket = &buckets[enumerator->_pi++];
        if (bucket->_state == NSHashBucketOccupied) {
            return (void *)bucket->_item;
        }
    }
    return NULL;
}

void NSEndHashTableEnumeration(NSHashEnumerator *enumerator) {
    enumerator->_pi = enumerator->_si;
}

NSUInteger NSCountHashTable(NSHashTable *table) {
    return [table count];
}

NSString *NSStringFromHashTable(NSHashTable *table) {
    return [NSString stringWithFormat:@"NSHashTable %lu entries", (unsigned long)[table count]];
}

NSArray *NSAllHashTableObjects(NSHashTable *table) {
    return [table allObjects];
}

/****************	Legacy	****************/

static NSUInteger _hashInt(NSHashTable *table, const void *item) {
#pragma unused(table)
    return (NSUInteger)(uintptr_t)item;
}

static BOOL _isEqualInt(NSHashTable *table, const void *a, const void *b) {
#pragma unused(table)
    return ((uintptr_t)a == (uintptr_t)b);
}

static void _noRetain(NSHashTable *table, const void *item) {
#pragma unused(table, item)
}

static void _noRelease(NSHashTable *table, void *item) {
#pragma unused(table, item)
}

static void _releasePointer(NSHashTable *table, void *item) {
#pragma unused(table)
    free(item);
}

static void _retainObject(NSHashTable *table, const void *item) {
#pragma unused(table)
    [(__bridge id)item retain];
}

static void _releaseObject(NSHashTable *table, void *item) {
#pragma unused(table)
    [(__bridge id)item release];
}

static NSUInteger _hashObject(NSHashTable *table, const void *item) {
#pragma unused(table)
    return (NSUInteger)[(__bridge id)item hash];
}

static BOOL _isEqualObject(NSHashTable *table, const void *a, const void *b) {
#pragma unused(table)
    return [(__bridge id)a isEqual:(__bridge id)b];
}

static NSUInteger _hashNonOwnedPointer(NSHashTable *table, const void *item) {
#pragma unused(table)
    return NSHashShiftedPointerHash(item);
}

static BOOL _isEqualNonOwnedPointer(NSHashTable *table, const void *a, const void *b) {
#pragma unused(table)
    return (a == b);
}

static NSString *_describeObject(NSHashTable *table, const void *item) {
#pragma unused(table)
    return [(__bridge id)item description];
}

const NSHashTableCallBacks NSIntegerHashCallBacks = {
    .hash = _hashInt,
    .isEqual = _isEqualInt,
    .retain = _noRetain,
    .release = _noRelease,
    .describe = NULL,
};

const NSHashTableCallBacks NSNonOwnedPointerHashCallBacks = {
    .hash = _hashNonOwnedPointer,
    .isEqual = _isEqualNonOwnedPointer,
    .retain = _noRetain,
    .release = _noRelease,
    .describe = NULL,
};

const NSHashTableCallBacks NSNonRetainedObjectHashCallBacks = {
    .hash = _hashObject,
    .isEqual = _isEqualObject,
    .retain = _noRetain,
    .release = _noRelease,
    .describe = _describeObject,
};

const NSHashTableCallBacks NSObjectHashCallBacks = {
    .hash = _hashObject,
    .isEqual = _isEqualObject,
    .retain = _retainObject,
    .release = _releaseObject,
    .describe = _describeObject,
};

const NSHashTableCallBacks NSOwnedObjectIdentityHashCallBacks = {
    .hash = _hashNonOwnedPointer,
    .isEqual = _isEqualNonOwnedPointer,
    .retain = _retainObject,
    .release = _releaseObject,
    .describe = _describeObject,
};

const NSHashTableCallBacks NSOwnedPointerHashCallBacks = {
    .hash = _hashNonOwnedPointer,
    .isEqual = _isEqualNonOwnedPointer,
    .retain = _noRetain,
    .release = _releasePointer,
    .describe = NULL,
};

const NSHashTableCallBacks NSPointerToStructHashCallBacks = {
    .hash = _hashNonOwnedPointer,
    .isEqual = _isEqualNonOwnedPointer,
    .retain = _noRetain,
    .release = _noRelease,
    .describe = NULL,
};

const NSHashTableCallBacks NSIntHashCallBacks = {
    .hash = _hashInt,
    .isEqual = _isEqualInt,
    .retain = _noRetain,
    .release = _noRelease,
    .describe = NULL,
};

NSHashTable *NSCreateHashTableWithZone(NSHashTableCallBacks callBacks, NSUInteger capacity, NSZone *zone) {
    return [[NSHashTable alloc] _initLegacyWithCallbacks:callBacks capacity:capacity];
}

NSHashTable *NSCreateHashTable(NSHashTableCallBacks callBacks, NSUInteger capacity) {
    return NSCreateHashTableWithZone(callBacks, capacity, NULL);
}

#endif /* defined __FOUNDATION_NSHASHTABLE_IMPL__ */
