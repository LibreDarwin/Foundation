/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSIndexSet_h
#define NSIndexSet_h

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>

@class NSString;

/* Class for managing a set of indexes.  The set of valid indexes is
 * 0 .. NSNotFound - 1.  NSIndexSet uses NSNotFound as a return value in
 * cases where the queried index doesn't exist in the set. */

@interface NSIndexSet : NSObject <NSCopying, NSMutableCopying, NSSecureCoding> {
@protected
    NSUInteger _length;       /* number of sorted, disjoint ranges */
    NSUInteger _capacity;     /* allocated slots in _ranges */
    NSRange *_ranges;
}

+ (instancetype)indexSet;
+ (instancetype)indexSetWithIndex:(NSUInteger)value;
+ (instancetype)indexSetWithIndexesInRange:(NSRange)range;

- (instancetype)init;
- (instancetype)initWithIndex:(NSUInteger)value;
- (instancetype)initWithIndexesInRange:(NSRange)range;
- (instancetype)initWithIndexSet:(NSIndexSet *)indexSet;

- (BOOL)isEqualToIndexSet:(NSIndexSet *)indexSet;
- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;

@property (readonly) NSUInteger count;
@property (readonly) NSUInteger firstIndex;
@property (readonly) NSUInteger lastIndex;

- (NSUInteger)indexGreaterThanIndex:(NSUInteger)value;
- (NSUInteger)indexLessThanIndex:(NSUInteger)value;
- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)value;
- (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)value;

- (NSUInteger)getIndexes:(NSUInteger *)indexBuffer maxCount:(NSUInteger)bufferSize inIndexRange:(NSRange *)range;
- (NSUInteger)countOfIndexesInRange:(NSRange)range;

- (BOOL)containsIndex:(NSUInteger)value;
- (BOOL)containsIndexesInRange:(NSRange)range;
- (BOOL)containsIndexes:(NSIndexSet *)indexSet;
- (BOOL)intersectsIndexesInRange:(NSRange)range;

- (void)enumerateIndexesUsingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block;
- (void)enumerateIndexesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block;
- (void)enumerateIndexesInRange:(NSRange)range options:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block;

- (NSUInteger)indexPassingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (NSUInteger)indexWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (NSUInteger)indexInRange:(NSRange)range options:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;

- (NSIndexSet *)indexesPassingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (NSIndexSet *)indexesWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;
- (NSIndexSet *)indexesInRange:(NSRange)range options:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate;

- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

- (id)copyWithZone:(NSZone *)zone;
- (id)mutableCopyWithZone:(NSZone *)zone;

- (NSString *)description;

@end

@interface NSMutableIndexSet : NSIndexSet

- (instancetype)init;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithIndexesInRange:(NSRange)range;
- (instancetype)initWithIndexSet:(NSIndexSet *)indexSet;

- (void)addIndexes:(NSIndexSet *)indexSet;
- (void)removeIndexes:(NSIndexSet *)indexSet;
- (void)removeAllIndexes;

- (void)addIndex:(NSUInteger)value;
- (void)removeIndex:(NSUInteger)value;

- (void)addIndexesInRange:(NSRange)range;
- (void)removeIndexesInRange:(NSRange)range;

/* For a positive delta, shifts the indexes in [index, NSNotFound] to the
 * right, inserting an empty space; for a negative delta, shifts them left,
 * deleting the indexes in [index + delta, index). */
- (void)shiftIndexesStartingAtIndex:(NSUInteger)index by:(NSInteger)delta;

@end

#endif /* NSIndexSet_h */