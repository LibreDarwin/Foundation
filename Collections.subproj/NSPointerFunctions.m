/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This implementation mirrors Apple's NSPointerFunctions personality
 * and memory semantics, twin of the port's NSPointerFunctions.h surface.
 *
 * The pointer collections copy NSPointerFunctions objects on input and
 * output, and so NSPointerFunctions is not usefully subclassed.
 */

#import "NSPointerFunctions.h"
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>
#import <string.h>

#if !defined(__FOUNDATION_NSPOINTERFUNCTIONS_IMPL__)
#define __FOUNDATION_NSPOINTERFUNCTIONS_IMPL__ 1

/* Bit masks for the option families.  Memory occupies bits 0-2, personality
 * occupies bits 8-10, CopyIn bit 16. */
#define NSPointerFunctionsMemoryFamilyMask      ((NSPointerFunctionsOptions)0x00000007)
#define NSPointerFunctionsPersonalityFamilyMask ((NSPointerFunctionsOptions)0x00000F00)

/* Personality helpers (twin of the C-function cluster NSMapTable/NSHashTable use). */

static NSUInteger NSPF_shiftedPointerHash(const void *item, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    register NSUInteger pointer = (NSUInteger)item;
    pointer >>= 4;
    pointer <<= 4;
    return pointer;
}

static BOOL NSPF_directEquality(const void *item1, const void *item2, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    return (item1 == item2);
}

static BOOL NSPF_objectEquality(const void *item1, const void *item2, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    return [(__bridge id)item1 isEqual:(__bridge id)item2];
}

static NSUInteger NSPF_objectHash(const void *item, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    return [(__bridge id)item hash];
}

static NSUInteger NSPF_stringHash(const void *item, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    register const char *str = (const char *)item;
    register NSUInteger hash = 0;
    while (*str) {
        hash = (hash << 5) - hash + (NSUInteger)(unsigned char)*str++;
    }
    return hash;
}

static BOOL NSPF_cStringEquality(const void *item1, const void *item2, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    return (strcmp((const char *)item1, (const char *)item2) == 0);
}

static NSUInteger NSPF_memoryHash(const void *item, NSUInteger (* _Nullable size)(const void *item)) {
    NSUInteger n = (size ? size(item) : 0);
    register const unsigned char *bytes = (const unsigned char *)item;
    register NSUInteger hash = 0;
    for (NSUInteger i = 0; i < n; i++) {
        hash = (hash << 5) - hash + (NSUInteger)bytes[i];
    }
    return hash;
}

static BOOL NSPF_memoryEquality(const void *item1, const void *item2, NSUInteger (* _Nullable size)(const void *item)) {
    NSUInteger n = (size ? size(item1) : 0);
    return (memcmp(item1, item2, n) == 0);
}

static NSUInteger NSPF_integerHash(const void *item, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    return (NSUInteger)item;    /* unshifted value as hash */
}

static BOOL NSPF_integerEquality(const void *item1, const void *item2, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(size)
    return ((NSUInteger)item1 == (NSUInteger)item2);
}

static void NSPF_relinquishNone(const void *item, NSUInteger (* _Nullable size)(const void *item)) {
#pragma unused(item, size)
}

static NSUInteger NSPF_sizeObject(const void *item) {
#pragma unused(item)
    return sizeof(id);
}

@implementation NSPointerFunctions {
    NSPointerFunctionsOptions _options;
    BOOL _copyIn;
    BOOL _hasMemoryManagement;
}

- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options {
    self = [super init];
    if (self) {
        _options = options;

        NSPointerFunctionsOptions memory = (options & NSPointerFunctionsMemoryFamilyMask);
        NSPointerFunctionsOptions personality = (options & NSPointerFunctionsPersonalityFamilyMask);
        BOOL copyIn = (options & NSPointerFunctionsCopyIn) ? YES : NO;

        /* memory */
        switch (memory) {
            case NSPointerFunctionsStrongMemory:      /* default; strong write-barrier; retain/release for objects */
            case NSPointerFunctionsWeakMemory:
                _hasMemoryManagement = YES;
                break;
            case NSPointerFunctionsOpaqueMemory:
            case NSPointerFunctionsMallocMemory:
            case NSPointerFunctionsMachVirtualMemory:
                _hasMemoryManagement = NO;
                break;
            default:
                _hasMemoryManagement = YES;
                break;
        }
        _copyIn = copyIn;

        /* personality (mutually exclusive) */
        switch (personality) {
            case NSPointerFunctionsObjectPersonality:             /* use -hash and -isEqual, object description */
                _hashFunction = NSPF_objectHash;
                _isEqualFunction = NSPF_objectEquality;
                break;
            case NSPointerFunctionsOpaquePersonality:             /* shifted pointer hash, direct equality */
                _hashFunction = NSPF_shiftedPointerHash;
                _isEqualFunction = NSPF_directEquality;
                break;
            case NSPointerFunctionsObjectPointerPersonality:      /* shifted pointer hash, direct equality, object description */
                _hashFunction = NSPF_shiftedPointerHash;
                _isEqualFunction = NSPF_directEquality;
                break;
            case NSPointerFunctionsCStringPersonality:            /* string hash, strcmp, UTF-8/ASCII description */
                _hashFunction = NSPF_stringHash;
                _isEqualFunction = NSPF_cStringEquality;
                break;
            case NSPointerFunctionsStructPersonality:             /* memory hash, memcmp (uses size function) */
                _hashFunction = NSPF_memoryHash;
                _isEqualFunction = NSPF_memoryEquality;
                break;
            case NSPointerFunctionsIntegerPersonality:            /* unshifted value as hash & equality */
                _hashFunction = NSPF_integerHash;
                _isEqualFunction = NSPF_integerEquality;
                break;
            default:
                _hashFunction = NULL;
                _isEqualFunction = NULL;
                break;
        }

        /* size: default object; struct/integer personalities require the caller to set */
        _sizeFunction = ((personality == NSPointerFunctionsObjectPersonality ||
                          personality == NSPointerFunctionsObjectPointerPersonality)
                         ? NSPF_sizeObject : NULL);

        _relinquishFunction = NSPF_relinquishNone;
        _acquireFunction = NULL;
        _usesStrongWriteBarrier = NO;
        _usesWeakReadAndWriteBarriers = NO;
    }
    return self;
}

- (instancetype)initWithPointerFunctions:(NSPointerFunctions *)functions {
    return [self initWithOptions:(functions ? [functions _options] : 0)];
}

+ (NSPointerFunctions *)pointerFunctionsWithOptions:(NSPointerFunctionsOptions)options {
    return [[[self alloc] initWithOptions:options] autorelease];
}

- (NSPointerFunctionsOptions)_options {
    return _options;
}

- (id)copyWithZone:(NSZone *)zone {
    NSPointerFunctions *copy = [[NSPointerFunctions allocWithZone:zone] initWithOptions:_options];
    if (copy) {
        copy->_hashFunction = _hashFunction;
        copy->_isEqualFunction = _isEqualFunction;
        copy->_sizeFunction = _sizeFunction;
        copy->_descriptionFunction = _descriptionFunction;
        copy->_relinquishFunction = _relinquishFunction;
        copy->_acquireFunction = _acquireFunction;
        copy->_copyIn = _copyIn;
        copy->_hasMemoryManagement = _hasMemoryManagement;
        copy->_usesStrongWriteBarrier = _usesStrongWriteBarrier;
        copy->_usesWeakReadAndWriteBarriers = _usesWeakReadAndWriteBarriers;
    }
    return copy;
}

@end

#endif // defined __FOUNDATION_NSPOINTERFUNCTIONS_IMPL__
