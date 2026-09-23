/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSOrderedSet_h
#define NSOrderedSet_h

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSEnumerator.h>

@class NSSortDescriptor;

@interface NSOrderedSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSSecureCoding, NSFastEnumeration> {
    NSArray *_osArray;
}

@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfObject:(ObjectType)object;
- (instancetype)init;
- (instancetype)initWithObjects:(const ObjectType _Nonnull [_Nullable])objects count:(NSUInteger)count;

@end

@interface NSOrderedSet<ObjectType> (NSExtendedOrderedSet)

- (ObjectType)firstObject;
- (ObjectType)lastObject;
- (BOOL)isEqualToOrderedSet:(NSOrderedSet<ObjectType> *)other;
- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;
- (BOOL)containsObject:(ObjectType)object;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)index;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (NSEnumerator<ObjectType> *)reverseObjectEnumerator;
- (NSOrderedSet<ObjectType> *)reversedOrderedSet;
- (NSArray<ObjectType> *)array;
- (NSSet<ObjectType> *)set;
- (id)copyWithZone:(NSZone *)zone;
- (id)mutableCopyWithZone:(NSZone *)zone;

- (NSUInteger)indexOfObject:(ObjectType)object inSortedRange:(NSRange)range
                    options:(NSBinarySearchingOptions)options
             usingComparator:(NSComparator)cmptr;

- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparator)cmptr;
- (NSArray<ObjectType> *)sortedArrayWithOptions:(NSSortOptions)options usingComparator:(NSComparator)cmptr;
- (NSArray<ObjectType> *)sortedArrayUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;

- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained _Nullable[_Nonnull])stackbuf
                                    count:(NSUInteger)len;

@end

@interface NSOrderedSet<ObjectType> (NSOrderedSetCreation)

+ (instancetype)orderedSet;
+ (instancetype)orderedSetWithObject:(ObjectType)object;
+ (instancetype)orderedSetWithObjects:(const ObjectType _Nonnull [_Nonnull])objects count:(NSUInteger)count;
+ (instancetype)orderedSetWithObjects:(ObjectType)firstObject, ...;
+ (instancetype)orderedSetWithOrderedSet:(NSOrderedSet<ObjectType> *)set;
+ (instancetype)orderedSetWithOrderedSet:(NSOrderedSet<ObjectType> *)set range:(NSRange)range copyItems:(BOOL)copyItems;
+ (instancetype)orderedSetWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)orderedSetWithArray:(NSArray<ObjectType> *)array range:(NSRange)range copyItems:(BOOL)copyItems;
+ (instancetype)orderedSetWithSet:(NSSet<ObjectType> *)set;
+ (instancetype)orderedSetWithSet:(NSSet<ObjectType> *)set copyItems:(BOOL)copyItems;

- (instancetype)initWithObject:(ObjectType)object;
- (instancetype)initWithObjects:(ObjectType)firstObject, ...;
- (instancetype)initWithOrderedSet:(NSOrderedSet<ObjectType> *)set;
- (instancetype)initWithOrderedSet:(NSOrderedSet<ObjectType> *)set copyItems:(BOOL)copyItems;
- (instancetype)initWithOrderedSet:(NSOrderedSet<ObjectType> *)set range:(NSRange)range copyItems:(BOOL)copyItems;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array copyItems:(BOOL)copyItems;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array range:(NSRange)range copyItems:(BOOL)copyItems;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set copyItems:(BOOL)copyItems;

@end

@interface NSMutableOrderedSet<ObjectType> : NSOrderedSet<ObjectType>

+ (instancetype)orderedSetWithCapacity:(NSUInteger)capacity;

- (instancetype)init;
- (instancetype)initWithCapacity:(NSUInteger)capacity;

- (void)insertObject:(ObjectType)object atIndex:(NSUInteger)index;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(ObjectType)object;

- (void)addObject:(ObjectType)object;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)setObject:(ObjectType)object atIndex:(NSUInteger)index;
- (void)exchangeObjectAtIndex:(NSUInteger)index1 withObjectAtIndex:(NSUInteger)index2;
- (void)removeAllObjects;
- (void)removeObject:(ObjectType)object;

- (void)sortUsingComparator:(NSComparator)cmptr;
- (void)sortWithOptions:(NSSortOptions)options usingComparator:(NSComparator)cmptr;
- (void)sortRange:(NSRange)range options:(NSSortOptions)options usingComparator:(NSComparator)cmptr;
- (void)sortUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;

@end

#endif /* NSOrderedSet_h */