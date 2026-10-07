/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSValue.h>
#import <dispatch/dispatch.h>

#include <regex.h>

#import "PredicateInternal.h"
@interface NSExpression (PredicateInternal)
- (NSString *)_NSPredicateDescription;
@end


@interface NSComparisonPredicate () {
@private
    NSExpression *_leftExpression;
    NSExpression *_rightExpression;
    NSPredicateOperatorType _predicateOperatorType;
    NSComparisonPredicateModifier _comparisonPredicateModifier;
    NSComparisonPredicateOptions _options;
    SEL _customSelector;
}
@end

/* Simple regex cache keyed by "pattern\0options". */
static NSMutableDictionary *_NSPSRegexCache(void) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

static BOOL _NSPredicateRegexMatch(NSString *pattern, NSString *subject, BOOL caseInsensitive) {
    if (pattern == nil || subject == nil) return NO;
    NSString *key = [NSString stringWithFormat:@"%d:%@", caseInsensitive ? 1 : 0, pattern];
    NSValue *boxed = [_NSPSRegexCache() objectForKey:key];
    regex_t *re = NULL;
    if (boxed == nil) {
        re = malloc(sizeof(regex_t));
        int rc = regcomp(re, [pattern UTF8String], REG_EXTENDED | (caseInsensitive ? REG_ICASE : 0));
        if (rc != 0) {
            free(re);
            [NSException raise:NSInvalidArgumentException format:@"Unable to compile regular expression \"%@\"", pattern];
        }
        [_NSPSRegexCache() setObject:[NSValue valueWithPointer:re] forKey:key];
    } else {
        re = [boxed pointerValue];
    }
    int rc = regexec(re, [subject UTF8String], 0, NULL, 0);
    return rc == 0;
}

/* Translate a LIKE pattern to an anchored regular expression. */
static NSString *_NSPredicateLikeToRegex(NSString *pattern) {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"^"];
    for (NSUInteger i = 0; i < pattern.length; i++) {
        unichar c = [pattern characterAtIndex:i];
        switch (c) {
            case '*': [out appendString:@".*"]; break;
            case '?': [out appendString:@"."]; break;
            default:
                if (c == '\\' || c == '.' || c == '+' || c == '(' || c == ')' ||
                    c == '[' || c == ']' || c == '{' || c == '}' || c == '^' ||
                    c == '$' || c == '|') {
                    [out appendFormat:@"\\%C", c];
                } else if (c == '\n') {
                    [out appendString:@"\\n"];
                } else {
                    [out appendFormat:@"%C", c];
                }
                break;
        }
    }
    [out appendString:@"$"];
    return out;
}

/* Compare two values; returns -1, 0, or 1.  Sets *comparable=NO when the
 * values are not orderable for the given options. */
static int _NSPredicateCompareValues(id lhs, id rhs, NSComparisonPredicateOptions options, BOOL *comparable) {
    *comparable = NO;
    if (lhs == nil || rhs == nil) return 0;
    NSComparisonResult result;

    if ([lhs isKindOfClass:[NSString class]] && [rhs isKindOfClass:[NSString class]] &&
        (options & (NSCaseInsensitivePredicateOption | NSDiacriticInsensitivePredicateOption))) {
        result = [(NSString *)lhs compare:(NSString *)rhs options:(NSStringCompareOptions)options];
        *comparable = YES;
        return (int)result;
    }
    if ([lhs isKindOfClass:[NSNumber class]] && [rhs isKindOfClass:[NSNumber class]] && options == 0) {
        result = [(NSNumber *)lhs compare:(NSNumber *)rhs];
        *comparable = YES;
        return (int)result;
    }
    if ([lhs isKindOfClass:[NSString class]] && [rhs isKindOfClass:[NSString class]] && options == 0) {
        result = [(NSString *)lhs compare:(NSString *)rhs];
        *comparable = YES;
        return (int)result;
    }
    /* Generic compare: */
    if ([lhs respondsToSelector:@selector(compare:)] && [rhs respondsToSelector:@selector(compare:)] && options == 0) {
        result = [lhs compare:rhs];
        *comparable = YES;
        return (int)result;
    }
    return 0;
}

static BOOL _NSPredicateValuesEqual(id lhs, id rhs, NSComparisonPredicateOptions options) {
    if (lhs == nil && rhs == nil) return YES;
    if (lhs == nil || rhs == nil) return NO;
    BOOL comparable;
    if (options != 0 && [lhs isKindOfClass:[NSString class]] && [rhs isKindOfClass:[NSString class]]) {
        return _NSPredicateCompareValues(lhs, rhs, options, &comparable) == 0;
    }
    return [lhs isEqual:rhs];
}

static BOOL _NSPredicateStringHasOptionPrefix(NSString *left, NSString *right, NSComparisonPredicateOptions options) {
    if (options == 0) return [left hasPrefix:right];
    NSRange r = [left rangeOfString:right options:(NSStringCompareOptions)options | NSAnchoredSearch];
    return r.location != NSNotFound;
}

static BOOL _NSPredicateStringHasOptionSuffix(NSString *left, NSString *right, NSComparisonPredicateOptions options) {
    if (options == 0) return [left hasSuffix:right];
    NSRange r = [left rangeOfString:right options:(NSStringCompareOptions)options | NSAnchoredSearch | NSBackwardsSearch];
    return r.location != NSNotFound;
}

static BOOL _NSPredicateStringContainsOption(NSString *left, NSString *right, NSComparisonPredicateOptions options) {
    NSRange r = [left rangeOfString:right options:(NSStringCompareOptions)options];
    return r.location != NSNotFound;
}

/* Apply a single comparison.  lhs/rhs are already evaluated values. */
static BOOL _NSPPredicatePerformCompare(id lhs, id rhs, NSPredicateOperatorType type,
                                        NSComparisonPredicateOptions options, SEL customSelector) {
    if (customSelector != NULL) {
        if (lhs == nil || ![lhs respondsToSelector:customSelector]) return NO;
        id result = [lhs performSelector:customSelector withObject:rhs];
        return result ? [result boolValue] : NO;
    }
    switch (type) {
        case NSEqualToPredicateOperatorType:
            return _NSPredicateValuesEqual(lhs, rhs, options);
        case NSNotEqualToPredicateOperatorType:
            return !_NSPredicateValuesEqual(lhs, rhs, options);
        case NSLessThanPredicateOperatorType:
        case NSLessThanOrEqualToPredicateOperatorType:
        case NSGreaterThanPredicateOperatorType:
        case NSGreaterThanOrEqualToPredicateOperatorType: {
            BOOL comparable = NO;
            int cmp = _NSPredicateCompareValues(lhs, rhs, options, &comparable);
            if (!comparable) return NO;
            switch (type) {
                case NSLessThanPredicateOperatorType: return cmp < 0;
                case NSLessThanOrEqualToPredicateOperatorType: return cmp <= 0;
                case NSGreaterThanPredicateOperatorType: return cmp > 0;
                default: return cmp >= 0;
            }
        }
        case NSContainsPredicateOperatorType: {
            if (![lhs isKindOfClass:[NSString class]] || ![rhs isKindOfClass:[NSString class]]) return NO;
            return _NSPredicateStringContainsOption(lhs, rhs, options);
        }
        case NSBeginsWithPredicateOperatorType: {
            if (![lhs isKindOfClass:[NSString class]] || ![rhs isKindOfClass:[NSString class]]) return NO;
            return _NSPredicateStringHasOptionPrefix(lhs, rhs, options);
        }
        case NSEndsWithPredicateOperatorType: {
            if (![lhs isKindOfClass:[NSString class]] || ![rhs isKindOfClass:[NSString class]]) return NO;
            return _NSPredicateStringHasOptionSuffix(lhs, rhs, options);
        }
        case NSMatchesPredicateOperatorType: {
            if (![lhs isKindOfClass:[NSString class]] || ![rhs isKindOfClass:[NSString class]]) return NO;
            return _NSPredicateRegexMatch(rhs, lhs, (options & NSCaseInsensitivePredicateOption) != 0);
        }
        case NSLikePredicateOperatorType: {
            if (![lhs isKindOfClass:[NSString class]] || ![rhs isKindOfClass:[NSString class]]) return NO;
            return _NSPredicateRegexMatch(_NSPredicateLikeToRegex(rhs), lhs, (options & NSCaseInsensitivePredicateOption) != 0);
        }
        case NSInPredicateOperatorType: {
            if (![rhs respondsToSelector:@selector(containsObject:)]) return NO;
            return [rhs containsObject:lhs];
        }
        case NSBetweenPredicateOperatorType: {
            if (![rhs isKindOfClass:[NSArray class]]) return NO;
            NSArray *bounds = rhs;
            if (bounds.count != 2) return NO;
            BOOL comparable;
            int lowCmp = _NSPredicateCompareValues(lhs, bounds[0], options, &comparable);
            int highCmp = _NSPredicateCompareValues(lhs, bounds[1], options, &comparable);
            if (!comparable) return NO;
            return lowCmp >= 0 && highCmp <= 0;
        }
        default:
            return NO;
    }
}

@implementation NSComparisonPredicate

+ (NSComparisonPredicate *)predicateWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs modifier:(NSComparisonPredicateModifier)modifier type:(NSPredicateOperatorType)type options:(NSComparisonPredicateOptions)options {
    return [[self alloc] initWithLeftExpression:lhs rightExpression:rhs modifier:modifier type:type options:options];
}

+ (NSComparisonPredicate *)predicateWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs customSelector:(SEL)selector {
    return [[self alloc] initWithLeftExpression:lhs rightExpression:rhs customSelector:selector];
}

- (instancetype)initWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs modifier:(NSComparisonPredicateModifier)modifier type:(NSPredicateOperatorType)type options:(NSComparisonPredicateOptions)options {
    if (lhs == nil || rhs == nil) {
        [NSException raise:NSInvalidArgumentException format:@"predicate requires both left and right expressions"];
    }
    if ((self = [super init])) {
        _leftExpression = [lhs copy];
        _rightExpression = [rhs copy];
        _comparisonPredicateModifier = modifier;
        _predicateOperatorType = type;
        _options = options;
        [self _setPredicateFormat:[self _generateFormatString]];
    }
    return self;
}

- (instancetype)initWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs customSelector:(SEL)selector {
    if ((self = [super init])) {
        _leftExpression = [lhs copy];
        _rightExpression = [rhs copy];
        _comparisonPredicateModifier = NSDirectPredicateModifier;
        _predicateOperatorType = NSCustomSelectorPredicateOperatorType;
        _options = 0;
        _customSelector = selector;
        [self _setPredicateFormat:[self _generateFormatString]];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    if (self = [super initWithCoder:coder]) {
        _leftExpression = [coder decodeObjectOfClass:[NSExpression class] forKey:@"NS.lhs"];
        _rightExpression = [coder decodeObjectOfClass:[NSExpression class] forKey:@"NS.rhs"];
        if (_leftExpression == nil || _rightExpression == nil) {
            [NSException raise:NSInvalidArgumentException format:@"predicate coder data is invalid"];
        }
        _predicateOperatorType = (NSPredicateOperatorType)[coder decodeIntForKey:@"NS.predicateOperatorType"];
        _options = [coder decodeIntegerForKey:@"NS.options"];
        _comparisonPredicateModifier = (NSComparisonPredicateModifier)[coder decodeIntForKey:@"NS.modifier"];
        _customSelector = NULL;
        NSString *selName = [coder decodeObjectOfClass:[NSString class] forKey:@"NS.customSelector"];
        if (selName.length) _customSelector = NSSelectorFromString(selName);
        [self _setPredicateFormat:[self _generateFormatString]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    [coder encodeObject:_leftExpression forKey:@"NS.lhs"];
    [coder encodeObject:_rightExpression forKey:@"NS.rhs"];
    [coder encodeInt:(int)_predicateOperatorType forKey:@"NS.predicateOperatorType"];
    [coder encodeInteger:(NSInteger)_options forKey:@"NS.options"];
    [coder encodeInt:(int)_comparisonPredicateModifier forKey:@"NS.modifier"];
    if (_customSelector != NULL) {
        [coder encodeObject:NSStringFromSelector(_customSelector) forKey:@"NS.customSelector"];
    }
}

- (NSString *)_generateFormatString {
    NSMutableString *out = [NSMutableString string];
    if (_comparisonPredicateModifier == NSAnyPredicateModifier) [out appendString:@"ANY "];
    else if (_comparisonPredicateModifier == NSAllPredicateModifier) [out appendString:@"ALL "];

    NSString *lhsDesc = [_leftExpression _NSPredicateDescription];
    NSString *rhsDesc = [_rightExpression _NSPredicateDescription];

    if (_customSelector != NULL) {
        [out appendFormat:@"Function(%@, \"%s:\", %@)", lhsDesc, sel_getName(_customSelector), rhsDesc];
        return out;
    }

    NSMutableString *opString = [NSMutableString string];
    BOOL wordOp = NO;
    switch (_predicateOperatorType) {
        case NSLessThanPredicateOperatorType: [opString appendString:@"<"]; break;
        case NSLessThanOrEqualToPredicateOperatorType: [opString appendString:@"<="]; break;
        case NSGreaterThanPredicateOperatorType: [opString appendString:@">"]; break;
        case NSGreaterThanOrEqualToPredicateOperatorType: [opString appendString:@">="]; break;
        case NSEqualToPredicateOperatorType: [opString appendString:@"=="]; break;
        case NSNotEqualToPredicateOperatorType: [opString appendString:@"!="]; break;
        case NSMatchesPredicateOperatorType: [opString appendString:@"MATCHES"]; wordOp = YES; break;
        case NSLikePredicateOperatorType: [opString appendString:@"LIKE"]; wordOp = YES; break;
        case NSBeginsWithPredicateOperatorType: [opString appendString:@"BEGINSWITH"]; wordOp = YES; break;
        case NSEndsWithPredicateOperatorType: [opString appendString:@"ENDSWITH"]; wordOp = YES; break;
        case NSContainsPredicateOperatorType: [opString appendString:@"CONTAINS"]; wordOp = YES; break;
        case NSInPredicateOperatorType: [opString appendString:@"IN"]; wordOp = YES; break;
        case NSBetweenPredicateOperatorType: [opString appendString:@"BETWEEN"]; wordOp = YES; break;
        default: [opString appendString:@"=="]; break;
    }
    if (wordOp && _options != 0) {
        NSMutableString *suffix = [NSMutableString string];
        if (_options & NSCaseInsensitivePredicateOption) [suffix appendString:@"c"];
        if (_options & NSDiacriticInsensitivePredicateOption) [suffix appendString:@"d"];
        if (suffix.length) [opString appendFormat:@"[%@]", suffix];
    }
    [out appendFormat:@"%@ %@ %@", lhsDesc, opString, rhsDesc];
    return out;
}

- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)variables {
    NSExpression *newLHS = _NSPredicateExpressionWithSubstitutions(_leftExpression, variables);
    NSExpression *newRHS = _NSPredicateExpressionWithSubstitutions(_rightExpression, variables);
    if ([self class] == [NSComparisonPredicate class] && _customSelector != NULL) {
        return [NSComparisonPredicate predicateWithLeftExpression:newLHS rightExpression:newRHS customSelector:_customSelector];
    }
    return [NSComparisonPredicate predicateWithLeftExpression:newLHS rightExpression:newRHS modifier:_comparisonPredicateModifier type:_predicateOperatorType options:_options];
}

- (BOOL)_evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings {
    NSMutableDictionary *context = [bindings mutableCopy];
    id rhsVal = [_rightExpression expressionValueWithObject:object context:context];

    if (_comparisonPredicateModifier == NSDirectPredicateModifier) {
        id lhsVal = [_leftExpression expressionValueWithObject:object context:context];
        return _NSPPredicatePerformCompare(lhsVal, rhsVal, _predicateOperatorType, _options, _customSelector);
    }

    id lhsVal = [_leftExpression expressionValueWithObject:object context:context];
    if (![lhsVal isKindOfClass:[NSArray class]] && ![lhsVal isKindOfClass:[NSSet class]] && ![lhsVal isKindOfClass:[NSOrderedSet class]]) {
        return _NSPPredicatePerformCompare(lhsVal, rhsVal, _predicateOperatorType, _options, _customSelector);
    }
    if (_comparisonPredicateModifier == NSAllPredicateModifier) {
        for (id element in lhsVal) {
            if (!_NSPPredicatePerformCompare(element, rhsVal, _predicateOperatorType, _options, _customSelector)) return NO;
        }
        return YES;
    }
    for (id element in lhsVal) {
        if (_NSPPredicatePerformCompare(element, rhsVal, _predicateOperatorType, _options, _customSelector)) return YES;
    }
    return NO;
}

- (NSPredicateOperatorType)predicateOperatorType { return _predicateOperatorType; }
- (NSComparisonPredicateModifier)comparisonPredicateModifier { return _comparisonPredicateModifier; }
- (NSExpression *)leftExpression { return _leftExpression; }
- (NSExpression *)rightExpression { return _rightExpression; }
- (SEL)customSelector { return _customSelector; }
- (NSComparisonPredicateOptions)options { return _options; }

@end