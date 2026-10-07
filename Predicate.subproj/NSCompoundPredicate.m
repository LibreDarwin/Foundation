/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import "PredicateInternal.h"

@interface NSCompoundPredicate () {
@private
    NSCompoundPredicateType _compoundPredicateType;
    NSArray *_subpredicates;
}
- (NSString *)_generateFormatString;
@end

@implementation NSCompoundPredicate

+ (NSCompoundPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates {
    return [[self alloc] initWithType:NSAndPredicateType subpredicates:subpredicates];
}

+ (NSCompoundPredicate *)orPredicateWithSubpredicates:(NSArray *)subpredicates {
    return [[self alloc] initWithType:NSOrPredicateType subpredicates:subpredicates];
}

+ (NSCompoundPredicate *)notPredicateWithSubpredicate:(NSPredicate *)predicate {
    if (predicate == nil) {
        [NSException raise:NSInvalidArgumentException format:@"notPredicateWithSubpredicate: requires a non-nil predicate"];
    }
    return [[self alloc] initWithType:NSNotPredicateType subpredicates:@[predicate]];
}

- (instancetype)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates {
    if (subpredicates == nil) {
        [NSException raise:NSInvalidArgumentException format:@"subpredicates must be non-nil"];
    }
    if ((self = [super init])) {
        _compoundPredicateType = type;
        _subpredicates = [subpredicates copy];
        [self _setPredicateFormat:[self _generateFormatString]];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    if (self = [super initWithCoder:coder]) {
        _compoundPredicateType = (NSCompoundPredicateType)[coder decodeIntForKey:@"NS.compoundPredicateType"];
        _subpredicates = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSPredicate class], [NSArray class], nil] forKey:@"NS.subpredicates"];
        if (_subpredicates == nil) {
            [NSException raise:NSInvalidArgumentException format:@"predicate coder data is invalid"];
        }
        [self _setPredicateFormat:[self _generateFormatString]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    [coder encodeInt:(int)_compoundPredicateType forKey:@"NS.compoundPredicateType"];
    [coder encodeObject:_subpredicates forKey:@"NS.subpredicates"];
}

- (NSCompoundPredicateType)compoundPredicateType {
    return _compoundPredicateType;
}

- (NSArray *)subpredicates {
    return _subpredicates;
}

- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)variables {
    if (_compoundPredicateType == NSNotPredicateType) {
        NSPredicate *sub = [[_subpredicates objectAtIndex:0] predicateWithSubstitutionVariables:variables];
        return [NSCompoundPredicate notPredicateWithSubpredicate:sub];
    }
    NSMutableArray *newSubs = [NSMutableArray arrayWithCapacity:_subpredicates.count];
    for (NSPredicate *sub in _subpredicates) {
        [newSubs addObject:[sub predicateWithSubstitutionVariables:variables]];
    }
    if (_compoundPredicateType == NSAndPredicateType) {
        return [NSCompoundPredicate andPredicateWithSubpredicates:newSubs];
    }
    return [NSCompoundPredicate orPredicateWithSubpredicates:newSubs];
}

- (BOOL)_evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings {
    switch (_compoundPredicateType) {
        case NSNotPredicateType:
            return ![[_subpredicates objectAtIndex:0] evaluateWithObject:object substitutionVariables:bindings];
        case NSAndPredicateType: {
            for (NSPredicate *sub in _subpredicates) {
                if (![sub evaluateWithObject:object substitutionVariables:bindings]) return NO;
            }
            return YES;
        }
        case NSOrPredicateType: {
            for (NSPredicate *sub in _subpredicates) {
                if ([sub evaluateWithObject:object substitutionVariables:bindings]) return YES;
            }
            return NO;
        }
    }
    return NO;
}

- (NSString *)_generateFormatString {
    if (_compoundPredicateType == NSNotPredicateType) {
        NSPredicate *sub = [_subpredicates objectAtIndex:0];
        if ([sub isKindOfClass:[NSCompoundPredicate class]] && [(NSCompoundPredicate *)sub compoundPredicateType] != NSNotPredicateType) {
            return [NSString stringWithFormat:@"NOT (%@)", sub.predicateFormat];
        }
        return [NSString stringWithFormat:@"NOT %@", sub.predicateFormat];
    }
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0;
    for (NSPredicate *sub in _subpredicates) {
        NSString *piece = sub.predicateFormat;
        if ([sub isKindOfClass:[NSCompoundPredicate class]] && [(NSCompoundPredicate *)sub compoundPredicateType] != _compoundPredicateType) {
            piece = [NSString stringWithFormat:@"(%@)", piece];
        }
        if (i++ > 0) [out appendFormat:_compoundPredicateType == NSAndPredicateType ? @" AND " : @" OR "];
        [out appendString:piece];
    }
    return out;
}

@end