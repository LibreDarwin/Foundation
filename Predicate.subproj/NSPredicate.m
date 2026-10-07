/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSPredicate.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import "PredicateInternal.h"

@interface NSPredicate () {
@private
    NSString *_predicateFormat;
}
@end

@interface _NSConstantPredicate : NSPredicate
- (instancetype)initWithValue:(BOOL)value;
- (void)_setConstantValue:(BOOL)value;
@end

@interface _NSBlockPredicate : NSPredicate {
    BOOL (^_block)(id, NSDictionary *);
}
- (void)_setBlock:(BOOL (^)(id, NSDictionary *))block;
@end

@implementation NSPredicate

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat argumentArray:(NSArray *)arguments {
    if (predicateFormat == nil) {
        [NSException raise:NSInvalidArgumentException format:@"predicateWithFormat: got nil format"];
    }
    return _NSPredicateParseFormat(predicateFormat, arguments);
}

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat, ... {
    va_list args;
    va_start(args, predicateFormat);
    NSPredicate *p = [self predicateWithFormat:predicateFormat arguments:args];
    va_end(args);
    return p;
}

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat arguments:(va_list)argList {
    if (predicateFormat == nil) {
        [NSException raise:NSInvalidArgumentException format:@"predicateWithFormat: got nil format"];
    }
    NSArray *args = _NSPredicateCollectArguments(predicateFormat, argList);
    return _NSPredicateParseFormat(predicateFormat, args);
}

+ (NSPredicate *)predicateWithValue:(BOOL)value {
    return [[_NSConstantPredicate alloc] initWithValue:value];
}

+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id, NSDictionary *))block {
    if (block == nil) {
        [NSException raise:NSInvalidArgumentException format:@"predicateWithBlock: got nil block"];
    }
    _NSBlockPredicate *p = [[_NSBlockPredicate alloc] init];
    [p _setBlock:block];
    return p;
}

- (NSString *)predicateFormat {
    return _predicateFormat;
}

- (void)_setPredicateFormat:(NSString *)format {
    _predicateFormat = [format copy];
}

- (instancetype)predicateWithSubstitutionVariables:(NSDictionary *)variables {
    return self;
}

- (BOOL)evaluateWithObject:(id)object {
    return [self evaluateWithObject:object substitutionVariables:nil];
}

- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings {
    if (_predicateFlags._evaluationBlocked) {
        [NSException raise:NSGenericException format:@"This predicate has not been allowed evaluation because it was created with a secure coding mechanism"];
    }
    return [self _evaluateWithObject:object substitutionVariables:bindings];
}

- (BOOL)_evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings {
    [NSException raise:NSGenericException format:@"predicate evaluation not overridden"];
    return NO;
}

- (void)allowEvaluation {
    _predicateFlags._evaluationBlocked = 0;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    if (self = [super init]) {
        _predicateFlags._evaluationBlocked = 1;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (_predicateFlags._evaluationBlocked == 0 && [self isKindOfClass:[_NSBlockPredicate class]]) {
        [NSException raise:NSGenericException format:@"This predicate object cannot be encoded because it contains a block that cannot be serialized"];
    }
    [NSException raise:NSGenericException format:@"Unable to encode predicate of class %@", NSStringFromClass([self class])];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (NSString *)description {
    return self.predicateFormat;
}

@end

@implementation _NSConstantPredicate {
    BOOL _value;
}

- (instancetype)initWithValue:(BOOL)value {
    if ((self = [super init])) {
        [self _setConstantValue:value];
    }
    return self;
}

- (void)_setConstantValue:(BOOL)value {
    _value = value;
    [self _setPredicateFormat:value ? @"TRUEPREDICATE" : @"FALSEPREDICATE"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self _setConstantValue:[coder decodeBoolForKey:@"NS._value"]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    [coder encodeBool:_value forKey:@"NS._value"];
}

- (BOOL)_evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings {
    return _value;
}

@end

@implementation _NSBlockPredicate

- (instancetype)init {
    if ((self = [super init])) {
        [self _setPredicateFormat:@"TRUEPREDICATE"];
    }
    return self;
}

- (void)_setBlock:(BOOL (^)(id, NSDictionary *))block {
    _block = [block copy];
}

- (BOOL)_evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings {
    return _block ? _block(object, bindings) : NO;
}

@end

@implementation NSArray (NSPredicateSupport)

- (NSArray *)filteredArrayUsingPredicate:(NSPredicate *)predicate {
    NSMutableArray *result = [NSMutableArray array];
    for (id object in self) {
        if ([predicate evaluateWithObject:object]) {
            [result addObject:object];
        }
    }
    return result;
}

@end

@implementation NSMutableArray (NSPredicateSupport)

- (void)filterUsingPredicate:(NSPredicate *)predicate {
    NSArray *kept = [[self copy] filteredArrayUsingPredicate:predicate];
    [self removeAllObjects];
    [self addObjectsFromArray:kept];
}

@end

@implementation NSSet (NSPredicateSupport)

- (NSSet *)filteredSetUsingPredicate:(NSPredicate *)predicate {
    NSMutableSet *result = [NSMutableSet set];
    for (id object in self) {
        if ([predicate evaluateWithObject:object]) {
            [result addObject:object];
        }
    }
    return result;
}

@end

@implementation NSMutableSet (NSPredicateSupport)

- (void)filterUsingPredicate:(NSPredicate *)predicate {
    NSMutableArray *toRemove = [NSMutableArray array];
    for (id object in self) {
        if (![predicate evaluateWithObject:object]) {
            [toRemove addObject:object];
        }
    }
    [self minusSet:[NSSet setWithArray:toRemove]];
}

@end

@implementation NSOrderedSet (NSPredicateSupport)

- (NSOrderedSet *)filteredOrderedSetUsingPredicate:(NSPredicate *)p {
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
    for (id object in self) {
        if ([p evaluateWithObject:object]) {
            [result addObject:object];
        }
    }
    return result;
}

@end

@implementation NSMutableOrderedSet (NSPredicateSupport)

- (void)filterUsingPredicate:(NSPredicate *)p {
    NSMutableArray *toRemove = [NSMutableArray array];
    for (id object in self) {
        if (![p evaluateWithObject:object]) {
            [toRemove addObject:object];
        }
    }
    for (id object in toRemove) {
        [self removeObject:object];
    }
}

@end