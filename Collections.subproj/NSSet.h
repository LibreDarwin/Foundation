/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSSet_h
#define NSSet_h

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSEnumerator.h>

@interface NSSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying> {
}

+ (instancetype)set;
+ (instancetype)setWithObject:(ObjectType)object;
+ (instancetype)setWithObjects:(const __unsafe_unretained ObjectType *)objects count:(NSUInteger)count;
+ (instancetype)setWithObjects:(ObjectType)firstObject, ...;
+ (instancetype)setWithSet:(NSSet<ObjectType> *)set;
+ (instancetype)setWithArray:(NSArray<ObjectType> *)array;

- (instancetype)init;
- (instancetype)initWithObjects:(const __unsafe_unretained ObjectType *)objects count:(NSUInteger)count;
- (instancetype)initWithObjects:(ObjectType)firstObject, ...;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set copyItems:(BOOL)copyItems;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;

@property (readonly) NSUInteger count;
- (ObjectType)member:(ObjectType)object;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (NSArray<ObjectType> *)allObjects;
- (ObjectType)anyObject;
- (BOOL)containsObject:(ObjectType)object;
- (BOOL)intersectsSet:(NSSet<ObjectType> *)otherSet;
- (BOOL)isEqualToSet:(NSSet<ObjectType> *)otherSet;
- (NSUInteger)hash;
- (id)copyWithZone:(NSZone *)zone;
- (id)mutableCopyWithZone:(NSZone *)zone;
- (BOOL)isSubsetOfSet:(NSSet<ObjectType> *)otherSet;
- (NSSet<ObjectType> *)setByAddingObject:(ObjectType)object;
- (NSSet<ObjectType> *)setByAddingObjectsFromSet:(NSSet<ObjectType> *)set;
- (NSSet<ObjectType> *)setByAddingObjectsFromArray:(NSArray<ObjectType> *)array;

@end

@interface NSMutableSet<ObjectType> : NSSet<ObjectType>
+ (instancetype)setWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)object;
- (void)removeObject:(ObjectType)object;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)intersectSet:(NSSet<ObjectType> *)otherSet;
- (void)minusSet:(NSSet<ObjectType> *)otherSet;
- (void)removeAllObjects;
- (void)unionSet:(NSSet<ObjectType> *)otherSet;
- (void)setSet:(NSSet<ObjectType> *)otherSet;
@end

@interface NSCountedSet<ObjectType> : NSMutableSet<ObjectType> {
    void *_counts;
}
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
- (NSUInteger)countForObject:(ObjectType)object;
@end

#endif /* NSSet_h */
