/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSPredicate.h.
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSOrderedSet.h>

#if !defined(__FOUNDATION_NSPREDICATE__)
#define __FOUNDATION_NSPREDICATE__ 1

@class NSDictionary, NSString;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

API_AVAILABLE(macos(10.4), ios(3.0), watchos(2.0), tvos(9.0))
@interface NSPredicate : NSObject <NSSecureCoding, NSCopying> {
    struct _predicateFlags {
        unsigned int _evaluationBlocked:1;
        unsigned int _reservedPredicateFlags:31;
    } _predicateFlags;
}

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat argumentArray:(nullable NSArray *)arguments;
+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat, ...;
+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat arguments:(va_list)argList;

+ (NSPredicate *)predicateWithValue:(BOOL)value;

+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id _Nullable evaluatedObject, NSDictionary * _Nullable bindings))block API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

@property (readonly, copy) NSString *predicateFormat;

- (instancetype)predicateWithSubstitutionVariables:(NSDictionary *)variables;

- (BOOL)evaluateWithObject:(nullable id)object;

- (BOOL)evaluateWithObject:(nullable id)object substitutionVariables:(nullable NSDictionary *)bindings API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));

- (void)allowEvaluation API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0));

@end

@interface NSArray<ObjectType> (NSPredicateSupport)
- (NSArray<ObjectType> *)filteredArrayUsingPredicate:(NSPredicate *)predicate;
@end

@interface NSMutableArray<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate;
@end

@interface NSSet<ObjectType> (NSPredicateSupport)
- (NSSet<ObjectType> *)filteredSetUsingPredicate:(NSPredicate *)predicate API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
@end

@interface NSMutableSet<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
@end

@interface NSOrderedSet<ObjectType> (NSPredicateSupport)
- (NSOrderedSet<ObjectType> *)filteredOrderedSetUsingPredicate:(NSPredicate *)p API_AVAILABLE(macos(10.7), ios(5.0), watchos(2.0), tvos(9.0));
@end

@interface NSMutableOrderedSet<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)p API_AVAILABLE(macos(10.7), ios(5.0), watchos(2.0), tvos(9.0));
@end

NS_HEADER_AUDIT_END(nullability, sendability)
#endif /* defined __FOUNDATION_NSPREDICATE__ */