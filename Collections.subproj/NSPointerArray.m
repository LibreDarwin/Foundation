/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSPointerArray mirrors Apple's pointer array: a resizable row of void*
 * slots whose per-entry acquire/relinquish semantics come from the
 * NSPointerFunctions used at init (memory mode, personality, CopyIn).  Weak
 * object memory stores each object through a private slot that holds it
 * weakly, so last release zeroes the read (pointerAtIndex:/fast enumeration
 * read NULL) while the slot still counts until -compact; strong object
 * memory retains on insert and releases on remove/replace/dealloc; NULL
 * pointers are first-class entries under every mode.
 *
 * The pointer collections copy NSPointerFunctions on input and output.
 */

#import <Foundation/NSPointerArray.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSString.h>

#include <CoreFoundation/CoreFoundation.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

#if !defined(__FOUNDATION_NSPOINTERARRAY_IMPL__)
#define __FOUNDATION_NSPOINTERARRAY_IMPL__ 1

/* Option-family masks, twin of NSPointerFunctions.m. */
#define NSPA_MEMORY_MASK        ((NSPointerFunctionsOptions)0x00000007)
#define NSPA_PERSONALITY_MASK   ((NSPointerFunctionsOptions)0x00000F00)
#define NSPA_COPYIN             ((NSPointerFunctionsOptions)0x00010000)

typedef NS_ENUM(NSUInteger, NSPAMemoryMode) {
    NSPAMemoryStrong = 0,
    NSPAMemoryZeroingWeak,
    NSPAMemoryOpaque,
    NSPAMemoryMalloc,
    NSPAMemoryMachVirtual,
    NSPAMemoryWeak,
};

typedef NS_ENUM(NSUInteger, NSPAPersonality) {
    NSPAPersonalityObject = 0,
    NSPAPersonalityOpaque,
    NSPAPersonalityObjectPointer,
    NSPAPersonalityCString,
    NSPAPersonalityStruct,
    NSPAPersonalityInteger,
};

@interface NSPointerFunctions (NSPointerArrayAccess)
- (NSPointerFunctionsOptions)_options;
@end

/* Weak-memory slot: index holds a +1 retain of the SLOT; the slot itself
 * holds the user's object weakly via the runtime manual weak APIs
 * (objc_storeWeak/objc_loadWeak), so the stored entry never keeps it alive
 * and reads NULL after the object's last release.  __weak is out: this tree
 * compiles with -fobjc-runtime=macosx, under which clang refuses to emit
 * __weak, so the weak storage lives behind an id-typed raw slot. */
@interface NSPAMemoryWeakSlot : NSObject {
@public __unsafe_unretained id _value;
}
- (void)setWeakValue:(id)object;
- (id)weakValue;
@end
@implementation NSPAMemoryWeakSlot
- (void)setWeakValue:(id)object {
    objc_storeWeak((id __autoreleasing *)(void *)&_value, object);
}
- (id)weakValue {
    return objc_loadWeak((id __autoreleasing *)(void *)&_value);
}
- (void)dealloc {
    objc_storeWeak((id __autoreleasing *)(void *)&_value, nil);
}
@end

@implementation NSPointerArray {
    void **_slots;
    NSUInteger _count;
    NSUInteger _capacity;
    NSPointerFunctions *_functions;
    NSUInteger _mutationCount;
}

+ (NSPointerArray *)pointerArrayWithOptions:(NSPointerFunctionsOptions)options {
    return [[self alloc] initWithOptions:options];
}

+ (NSPointerArray *)pointerArrayWithPointerFunctions:(NSPointerFunctions *)functions {
    return [[self alloc] initWithPointerFunctions:functions];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

static BOOL NSPAConfigurationUnsupported(NSPointerFunctionsOptions options) {
    NSUInteger memory = options & NSPA_MEMORY_MASK;
    if (memory == NSPointerFunctionsMallocMemory || memory == NSPointerFunctionsMachVirtualMemory) {
        return YES;
    }
    if ((options & NSPointerFunctionsIntegerPersonality) && (memory != NSPointerFunctionsOpaqueMemory)) {
        return YES;
    }
    return NO;
}

- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options {
    if (NSPAConfigurationUnsupported(options)) {
        [NSException raise:NSInternalInconsistencyException format:@"%@", @"Requested configuration not supported"];
    }
    return [self initWithPointerFunctions:[NSPointerFunctions pointerFunctionsWithOptions:options]];
}

- (instancetype)initWithPointerFunctions:(NSPointerFunctions *)functions {
    self = [super init];
    if (self) {
        if (functions == nil) {
            functions = [NSPointerFunctions pointerFunctionsWithOptions:0];
        }
        _functions = [functions copy];
        _capacity = 4;
        _slots = calloc(_capacity, sizeof(void *));
    }
    return self;
}

- (void)dealloc {
    for (NSUInteger i = 0; i < _count; i++) {
        if (_slots[i]) [self _relinquishPointer:_slots[i]];
    }
    free(_slots);
}

/* ---- derived semantics ---- */

- (NSPointerFunctionsOptions)_options {
    return [_functions _options];
}

- (NSPAMemoryMode)_memoryMode {
    return (NSPAMemoryMode)([self _options] & NSPA_MEMORY_MASK);
}

- (NSPAPersonality)_personality {
    return (NSPAPersonality)(([self _options] & NSPA_PERSONALITY_MASK) >> 8);
}

- (BOOL)_isWeak {
    NSPAMemoryMode m = [self _memoryMode];
    return (m == NSPAMemoryWeak || m == NSPAMemoryZeroingWeak);
}

- (BOOL)_isObjectPersonality {
    NSPAPersonality p = [self _personality];
    return (p == NSPAPersonalityObject || p == NSPAPersonalityObjectPointer);
}

- (BOOL)_isCopyIn {
    return (([self _options] & NSPA_COPYIN) != 0);
}

/* Store `pointer` into a fresh slot, returning the slot to place in the row.
 * NULL stays NULL under every mode. */
- (void *)_acquirePointer:(void *)pointer {
    if (pointer == NULL) return NULL;
    if ([self _isWeak]) {
        NSPAMemoryWeakSlot *slot = [[NSPAMemoryWeakSlot alloc] init];
        [slot setWeakValue:(__bridge id)pointer];
        return (void *)CFBridgingRetain(slot);
    }
    if ([self _isObjectPersonality]) {
        if ([self _memoryMode] == NSPAMemoryStrong) {
            if ([self _isCopyIn]) {
                id copy = [(__bridge id)pointer copy];
                return (void *)CFBridgingRetain(copy);
            }
            return (void *)CFRetain(pointer);
        }
        return pointer; /* opaque/malloc/mach: unsafe unretained */
    }
    if ([self _isCopyIn]) {
        switch ([self _personality]) {
            case NSPAPersonalityCString:
                return strdup((const char *)pointer);
            default:
                return pointer;
        }
    }
    return pointer;
}

/* Release what -_acquirePointer: installed for a slot being dropped. */
- (void)_relinquishPointer:(void *)pointer {
    if (pointer == NULL) return;
    if ([self _isWeak]) {
        CFBridgingRelease(pointer);
        return;
    }
    if ([self _isObjectPersonality]) {
        if ([self _memoryMode] == NSPAMemoryStrong) {
            CFRelease(pointer);
        }
        return;
    }
    if ([self _isCopyIn] && [self _personality] == NSPAPersonalityCString) {
        free(pointer);
    }
}

- (void)_ensureCapacityForAdditional:(NSUInteger)incoming {
    if (_count + incoming <= _capacity) return;
    while (_count + incoming > _capacity) {
        _capacity *= 2;
    }
    void **grown = realloc(_slots, _capacity * sizeof(void *));
    _slots = grown;
    memset(_slots + _count, 0, (_capacity - _count) * sizeof(void *));
}

- (void)_raiseIndexOutOfRange:(NSUInteger)index {
    [NSException raise:NSRangeException format:@"index %lu out of range (count = %lu)",
                (unsigned long)index, (unsigned long)_count];
}

/* ---- public surface ---- */

- (NSPointerFunctions *)pointerFunctions {
    return [_functions copy];
}

- (NSUInteger)count {
    return _count;
}

- (void)setCount:(NSUInteger)count {
    if (count == _count) return;
    if (count < _count) {
        for (NSUInteger i = count; i < _count; i++) {
            if (_slots[i]) [self _relinquishPointer:_slots[i]];
        }
        _count = count;
        memset(&_slots[_count], 0, (_capacity - _count) * sizeof(void *));
        _mutationCount++;
        return;
    }
    [self _ensureCapacityForAdditional:(count - _count)];
    memset(&_slots[_count], 0, (count - _count) * sizeof(void *));
    _count = count;
    _mutationCount++;
}

- (void *)pointerAtIndex:(NSUInteger)index {
    if (index >= _count) [self _raiseIndexOutOfRange:index];
    void *stored = _slots[index];
    if (stored == NULL) return NULL;
    if ([self _isWeak]) {
        NSPAMemoryWeakSlot *slot = (__bridge NSPAMemoryWeakSlot *)stored;
        return (__bridge void *)[slot weakValue];
    }
    return stored;
}

- (void)addPointer:(void *)pointer {
    _mutationCount++;
    [self _ensureCapacityForAdditional:1];
    _slots[_count] = [self _acquirePointer:pointer];
    _count++;
}

- (void)insertPointer:(void *)item atIndex:(NSUInteger)index {
    if (index > _count) [self _raiseIndexOutOfRange:index];
    _mutationCount++;
    [self _ensureCapacityForAdditional:1];
    memmove(&_slots[index + 1], &_slots[index], (_count - index) * sizeof(void *));
    _slots[index] = [self _acquirePointer:item];
    _count++;
}

- (void)removePointerAtIndex:(NSUInteger)index {
    if (index >= _count) {
        [NSException raise:NSInvalidArgumentException format:@"index %lu out of range (count = %lu)",
                    (unsigned long)index, (unsigned long)_count];
    }
    _mutationCount++;
    if (_slots[index]) [self _relinquishPointer:_slots[index]];
    memmove(&_slots[index], &_slots[index + 1], (_count - index - 1) * sizeof(void *));
    _count--;
    memset(&_slots[_count], 0, (_capacity - _count) * sizeof(void *));
}

- (void)replacePointerAtIndex:(NSUInteger)index withPointer:(void *)item {
    if (index >= _count) [self _raiseIndexOutOfRange:index];
    _mutationCount++;
    if (_slots[index]) [self _relinquishPointer:_slots[index]];
    _slots[index] = [self _acquirePointer:item];
}

- (void)compact {
    NSUInteger write = 0;
    for (NSUInteger read = 0; read < _count; read++) {
        void *keep = NULL;
        void *stored = _slots[read];
        if (stored != NULL) {
            if ([self _isWeak]) {
                if ([(__bridge NSPAMemoryWeakSlot *)stored weakValue] != nil) {
                    keep = stored;   /* still live */
                }
            } else {
                keep = stored;
            }
        }
        if (keep) {
            if (write != read) _slots[write] = keep;
            write++;
        } else if (stored) {
            [self _relinquishPointer:stored];
        }
    }
    _count = write;
    memset(&_slots[_count], 0, (_capacity - _count) * sizeof(void *));
    _mutationCount++;
}

- (id)copyWithZone:(NSZone *)zone {
    NSPointerArray *copy = [[NSPointerArray allocWithZone:zone] initWithPointerFunctions:_functions];
    [copy _ensureCapacityForAdditional:_count];
    for (NSUInteger i = 0; i < _count; i++) {
        copy->_slots[i] = [self _acquirePointer:[self pointerAtIndex:i]];
    }
    copy->_count = _count;
    return copy;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)objects count:(NSUInteger)stackbufCount {
    NSUInteger base = state->state;
    if (base >= _count) return 0;
    state->mutationsPtr = &_mutationCount;
    NSUInteger batch = stackbufCount;
    if (base + batch > _count) batch = _count - base;
    for (NSUInteger i = 0; i < batch; i++) {
        objects[i] = (__bridge id)[self pointerAtIndex:(base + i)];
    }
    state->itemsPtr = objects;
    state->state = base + batch;
    return batch;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSPointerFunctionsOptions options = 0;
    NSData *optionsData = [coder decodeObjectOfClass:[NSData class] forKey:@"pointerFunctions"];
    if (optionsData && [optionsData length] == sizeof(NSPointerFunctionsOptions)) {
        [optionsData getBytes:&options length:sizeof(NSPointerFunctionsOptions)];
    } else {
        options = 0;
    }
    self = [self initWithOptions:options];
    if (self) {
        NSArray *objects = [coder decodeObjectOfClass:[NSArray class] forKey:@"objects"];
        for (id object in objects) {
            [self addPointer:(__bridge void *)object];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSPointerFunctionsOptions options = [self _options];
    NSData *optionsData = [NSData dataWithBytes:&options length:sizeof(NSPointerFunctionsOptions)];
    [coder encodeObject:optionsData forKey:@"pointerFunctions"];
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:_count];
    for (NSUInteger i = 0; i < _count; i++) {
        void *p = [self pointerAtIndex:i];
        if (p) [objects addObject:(__bridge id)p];
    }
    [coder encodeObject:objects forKey:@"objects"];
}

@end

@implementation NSPointerArray (NSPointerArrayConveniences)

+ (NSPointerArray *)strongObjectsPointerArray {
    return [NSPointerArray pointerArrayWithOptions:(NSPointerFunctionsStrongMemory
                                                  | NSPointerFunctionsObjectPersonality)];
}

+ (NSPointerArray *)weakObjectsPointerArray {
    return [NSPointerArray pointerArrayWithOptions:(NSPointerFunctionsWeakMemory
                                                  | NSPointerFunctionsObjectPersonality)];
}

- (NSArray *)allObjects {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:_count];
    for (NSUInteger i = 0; i < _count; i++) {
        void *p = [self pointerAtIndex:i];
        if (p != NULL) [result addObject:(__bridge id)p];
    }
    return result;
}

@end

#endif // defined __FOUNDATION_NSPOINTERARRAY_IMPL__