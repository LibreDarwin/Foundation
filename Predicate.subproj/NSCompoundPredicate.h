/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSCompoundPredicate.h.
 */

#import <Foundation/NSPredicate.h>

#if !defined(__FOUNDATION_NSCOMPOUNDPREDICATE__)
#define __FOUNDATION_NSCOMPOUNDPREDICATE__ 1

@class NSArray;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef NS_ENUM(NSUInteger, NSCompoundPredicateType) {
    NSNotPredicateType = 0,
    NSAndPredicateType,
    NSOrPredicateType,
};

API_AVAILABLE(macos(10.4), ios(3.0), watchos(2.0), tvos(9.0))
@interface NSCompoundPredicate : NSPredicate

- (instancetype)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@property (readonly) NSCompoundPredicateType compoundPredicateType;
@property (readonly, copy) NSArray *subpredicates;

+ (NSCompoundPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates;
+ (NSCompoundPredicate *)orPredicateWithSubpredicates:(NSArray *)subpredicates;
+ (NSCompoundPredicate *)notPredicateWithSubpredicate:(NSPredicate *)predicate;

@end

NS_HEADER_AUDIT_END(nullability, sendability)
#endif /* defined __FOUNDATION_NSCOMPOUNDPREDICATE__ */