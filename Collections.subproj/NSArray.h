/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSArray_h
#define NSArray_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

@class NSEnumerator;
@class NSSortDescriptor;

typedef NS_OPTIONS(NSUInteger, NSBinarySearchingOptions) {
    NSBinarySearchingFirstEqual = (1UL << 8),
    NSBinarySearchingLastEqual = (1UL << 9),
    NSBinarySearchingInsertionIndex = (1UL << 10),
};

@interface NSArray<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>

+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const ObjectType _Nonnull [_Nullable])objects count:(NSUInteger)count;
+ (instancetype)arrayWithArray:(NSArray<ObjectType> *)array;

- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
- (BOOL)containsObject:(id)object;
- (BOOL)isEqualToArray:(NSArray<ObjectType> *)array;
- (NSUInteger)hash;
- (id)copyWithZone:(NSZone *)zone;
- (id)mutableCopyWithZone:(NSZone *)zone;
- (NSEnumerator *)objectEnumerator;
- (NSEnumerator *)reverseObjectEnumerator;
- (NSArray<ObjectType> *)sortedArrayUsingSelector:(SEL)comparator;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparator)cmptr;
- (NSArray<ObjectType> *)sortedArrayUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;

@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>

+ (instancetype)arrayWithCapacity:(NSUInteger)capacity;

- (void)addObject:(ObjectType)object;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(ObjectType)anObject;
- (void)setObject:(ObjectType)obj atIndexedSubscript:(NSUInteger)idx;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeAllObjects;
- (void)sortUsingSelector:(SEL)comparator;
- (void)sortUsingComparator:(NSComparator)cmptr;
- (void)sortUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;

@end

#endif /* NSArray_h */
