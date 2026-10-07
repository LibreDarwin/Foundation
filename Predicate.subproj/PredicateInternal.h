/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Internal helpers shared by the predicate and expression sources.  This
 * header is excluded from the generated umbrella; include it explicitly.
 */

#import <Foundation/NSPredicate.h>

#include <stdarg.h>

@class NSString, NSArray, NSPredicate, NSExpression;

@interface NSPredicate (PredicateInternal)
- (void)_setPredicateFormat:(NSString *)format;
- (BOOL)_evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings;
@end

FOUNDATION_EXPORT id _NSPredicateValueForKeyPath(id object, NSString *keyPath);
FOUNDATION_EXPORT NSPredicate *_NSPredicateParseFormat(NSString *format, NSArray *args);
FOUNDATION_EXPORT NSExpression *_NSPredicateParseExpressionFormat(NSString *format, NSArray *args);
FOUNDATION_EXPORT NSArray *_NSPredicateCollectArguments(NSString *format, va_list args);
FOUNDATION_EXPORT NSExpression *_NSPredicateExpressionWithSubstitutions(NSExpression *e, NSDictionary *bindings);
NSString *_NSPredicateDescription(id obj);
