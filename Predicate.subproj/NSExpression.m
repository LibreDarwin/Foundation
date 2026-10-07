/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSExpression.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSCoder.h>
#import <objc/message.h>
#import "PredicateInternal.h"

#include <regex.h>
#include <math.h>

/* ------------------------------------------------------------------ */
/*  Shared key-path resolver (also used by the comparison operators).  */
/* ------------------------------------------------------------------ */

static BOOL _NSPredicateIsCollection(id value) {
    return [value isKindOfClass:[NSArray class]] ||
           [value isKindOfClass:[NSSet class]] ||
           [value isKindOfClass:[NSOrderedSet class]];
}

static NSUInteger _NSPredicateCollectionCount(id collection) {
    if ([collection isKindOfClass:[NSArray class]]) return [(NSArray *)collection count];
    if ([collection isKindOfClass:[NSOrderedSet class]]) return [(NSOrderedSet *)collection count];
    return [(NSSet *)collection count];
}

static void _NSPredicateEnumerateCollection(id collection, void (^block)(id element)) {
    if ([collection isKindOfClass:[NSSet class]]) {
        for (id element in (NSSet *)collection) block(element);
    } else {
        for (id element in (NSArray *)collection) block(element);
    }
}

static NSArray *_NSPredicateCollectionObjects(id collection) {
    if ([collection isKindOfClass:[NSSet class]]) return [(NSSet *)collection allObjects];
    return (NSArray *)collection;
}

static BOOL _NSPredicateIsNumericKey(NSString *token) {
    if (token.length == 0) return NO;
    for (NSUInteger i = 0; i < token.length; i++) {
        unichar c = [token characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

static id _NSPredicateValueForKey(id object, NSString *key) {
    if (object == nil) return nil;
    if ([key isEqualToString:@"self"]) return object;
    if ([object isKindOfClass:[NSDictionary class]]) {
        return [(NSDictionary *)object objectForKey:key];
    }
    if ([object isKindOfClass:[NSArray class]]) {
        if (_NSPredicateIsNumericKey(key)) {
            NSUInteger index = (NSUInteger)strtoull([key UTF8String], NULL, 10);
            if (index < [(NSArray *)object count]) return [(NSArray *)object objectAtIndex:index];
            return nil;
        }
        NSMutableArray *mapped = [NSMutableArray array];
        for (id element in (NSArray *)object) {
            id v = _NSPredicateValueForKey(element, key);
            if (v) [mapped addObject:v];
        }
        return mapped;
    }
    if ([object isKindOfClass:[NSSet class]]) {
        if ([key isEqualToString:@"@count"]) return @([(NSSet *)object count]);
        return nil;
    }
    if ([object isKindOfClass:[NSOrderedSet class]]) {
        if ([key isEqualToString:@"@count"]) return @([(NSOrderedSet *)object count]);
        return nil;
    }
    return [object valueForKey:key];
}

static NSArray *_NSPredicateValuesForCollection(id collection, NSString *remainingPath) {
    NSMutableArray *values = [NSMutableArray array];
    _NSPredicateEnumerateCollection(collection, ^(id element) {
        if (remainingPath.length > 0) {
            id v = _NSPredicateValueForKeyPath(element, remainingPath);
            if (v) [values addObject:v];
        } else {
            [values addObject:element];
        }
    });
    return values;
}

id _NSPredicateValueForKeyPath(id object, NSString *keyPath) {
    if (object == nil || keyPath.length == 0) return object;
    if ([keyPath isEqualToString:@"self"]) return object;

    id current = object;
    NSString *remaining = keyPath;
    while (remaining.length > 0) {
        NSRange dot = [remaining rangeOfString:@"."];
        NSString *token;
        NSString *rest;
        if (dot.location == NSNotFound) {
            token = remaining;
            rest = @"";
        } else {
            token = [remaining substringToIndex:dot.location];
            rest = [remaining substringFromIndex:dot.location + 1];
        }

        if ([token hasPrefix:@"@"] && token.length > 1) {
            NSString *op = [token substringFromIndex:1];
            if ([op isEqualToString:@"count"]) {
                current = @(_NSPredicateCollectionCount(current));
            } else if ([op isEqualToString:@"sum"]) {
                double total = 0.0;
                for (id v in _NSPredicateValuesForCollection(current, rest)) {
                    if ([v isKindOfClass:[NSNumber class]]) total += [v doubleValue];
                }
                current = @(total);
                rest = @"";
            } else if ([op isEqualToString:@"avg"]) {
                NSArray *vals = _NSPredicateValuesForCollection(current, rest);
                double total = 0.0;
                for (id v in vals) {
                    if ([v isKindOfClass:[NSNumber class]]) total += [v doubleValue];
                }
                current = vals.count ? @(total / (double)vals.count) : @0;
                rest = @"";
            } else if ([op isEqualToString:@"min"]) {
                NSArray *vals = _NSPredicateValuesForCollection(current, rest);
                id best = nil;
                for (id v in vals) {
                    if (![v isKindOfClass:[NSNumber class]]) continue;
                    if (best == nil || [v doubleValue] < [best doubleValue]) best = v;
                }
                current = best ?: @0;
                rest = @"";
            } else if ([op isEqualToString:@"max"]) {
                NSArray *vals = _NSPredicateValuesForCollection(current, rest);
                id best = nil;
                for (id v in vals) {
                    if (![v isKindOfClass:[NSNumber class]]) continue;
                    if (best == nil || [v doubleValue] > [best doubleValue]) best = v;
                }
                current = best ?: @0;
                rest = @"";
            } else if ([op isEqualToString:@"firstObject"]) {
                NSArray *objs = _NSPredicateCollectionObjects(current);
                current = objs.count ? [objs objectAtIndex:0] : nil;
                rest = @"";
            } else if ([op isEqualToString:@"lastObject"]) {
                NSArray *objs = _NSPredicateCollectionObjects(current);
                current = objs.count ? [objs objectAtIndex:objs.count - 1] : nil;
                rest = @"";
            } else if ([op isEqualToString:@"distinctUnionOfObjects"] ||
                       [op isEqualToString:@"unionOfObjects"]) {
                NSArray *vals = _NSPredicateValuesForCollection(current, rest);
                if ([op hasPrefix:@"distinct"]) current = [[NSSet alloc] initWithArray:vals];
                else current = vals;
                rest = @"";
            } else if ([op isEqualToString:@"unionOfArrays"] ||
                       [op isEqualToString:@"distinctUnionOfArrays"]) {
                NSMutableArray *flat = [NSMutableArray array];
                for (id sub in _NSPredicateValuesForCollection(current, rest)) {
                    if ([sub isKindOfClass:[NSArray class]]) [flat addObjectsFromArray:sub];
                }
                if ([op hasPrefix:@"distinct"]) current = [[NSSet alloc] initWithArray:flat];
                else current = flat;
                rest = @"";
            } else if ([op isEqualToString:@"unionOfSets"] ||
                       [op isEqualToString:@"distinctUnionOfSets"]) {
                NSMutableSet *flat = [NSMutableSet set];
                for (id sub in _NSPredicateValuesForCollection(current, rest)) {
                    if ([sub isKindOfClass:[NSSet class]]) [flat unionSet:sub];
                }
                current = flat;
                rest = @"";
            } else {
                current = nil;
                rest = @"";
            }
            remaining = rest;
        } else {
            current = _NSPredicateValueForKey(current, token);
            remaining = rest;
        }
        if (current == nil) return nil;
    }
    return current;
}

/* ------------------------------------------------------------------ */
/*  Format-string parser.                                              */
/*                                                                     */
/*  Shared by +[NSExpression expressionWithFormat:] and                */
/*  +[NSPredicate predicateWithFormat:].  Operates on an immutable     */
/*  input string and a mutable cursor so the predicate grammar can     */
/*  backtrack cheaply.                                                 */
/* ------------------------------------------------------------------ */

#define _NSPREDICATE_RAISE(msg)      [NSException raise:NSInvalidArgumentException format:@"Unable to parse the format string \"%@\": " msg]

typedef struct {
    NSString *input;
    NSUInteger pos;
    NSArray *args;
} _NSPredicateStream;

static void _NSPSkipWhitespace(_NSPredicateStream *s) {
    NSUInteger n = s->input.length;
    while (s->pos < n) {
        unichar c = [s->input characterAtIndex:s->pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f') s->pos++;
        else break;
    }
}

static BOOL _NSPSymbol(_NSPredicateStream *s, NSString *sym) {
    NSUInteger n = s->input.length;
    if (s->pos + sym.length > n) return NO;
    if ([[s->input substringWithRange:NSMakeRange(s->pos, sym.length)] isEqualToString:sym]) {
        s->pos += sym.length;
        return YES;
    }
    return NO;
}

static BOOL _NSPSKeyword(_NSPredicateStream *s, NSString *kw) {
    NSUInteger n = s->input.length;
    if (s->pos + kw.length > n) return NO;
    if ([[s->input substringWithRange:NSMakeRange(s->pos, kw.length)] compare:kw options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        NSUInteger after = s->pos + kw.length;
        if (after < n) {
            unichar c = [s->input characterAtIndex:after];
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') return NO;
        }
        s->pos = after;
        return YES;
    }
    return NO;
}

static unichar _NSPSPeek(_NSPredicateStream *s) {
    if (s->pos >= s->input.length) return 0;
    return [s->input characterAtIndex:s->pos];
}

static BOOL _NSPsisIdentChar(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '_' || c == '$';
}

/* --- forward declarations -------------------------------- */
static NSExpression *_NSParseValueExpression(_NSPredicateStream *s);
static void _NSParseCheckEnd(_NSPredicateStream *s);

static NSExpression *_NSParsePrimary(_NSPredicateStream *s) {
    _NSPSkipWhitespace(s);
    unichar c = _NSPSPeek(s);
    if (c == 0) _NSPREDICATE_RAISE(@"expected an expression");

    /* Parenthesized arithmetic expression. */
    if (c == '(') {
        s->pos++;
        NSExpression *e = _NSParseValueExpression(s);
        _NSPSkipWhitespace(s);
        if (!_NSPSymbol(s, @")")) _NSPREDICATE_RAISE(@"expected closing paren");
        return e;
    }

    /* '%@' / '%K' argument placeholders. */
    if (c == '%') {
        s->pos++;
        if (s->pos >= s->input.length) _NSPREDICATE_RAISE(@"incomplete format specifier");
        unichar spec = [s->input characterAtIndex:s->pos];
        s->pos++;
        if (spec != '@' && spec != 'K') _NSPREDICATE_RAISE(@"unsupported format specifier");
        if (s->args == nil || s->args.count == 0) _NSPREDICATE_RAISE(@"no argument provided");
        id arg = [s->args objectAtIndex:0];
        NSMutableArray *tail = [NSMutableArray arrayWithArray:s->args];
        [tail removeObjectAtIndex:0];
        s->args = tail;
        if (spec == 'K') {
            if (![arg isKindOfClass:[NSString class]]) _NSPREDICATE_RAISE(@"%K requires a string argument");
            return [NSExpression expressionForKeyPath:arg];
        }
        return [NSExpression expressionForConstantValue:arg];
    }

    /* String literal. */
    if (c == '\'' || c == '"') {
        unichar quote = c;
        s->pos++;
        NSMutableString *buf = [NSMutableString string];
        while (s->pos < s->input.length) {
            unichar ch = [s->input characterAtIndex:s->pos];
            if (ch == quote) break;
            if (ch == '\\' && s->pos + 1 < s->input.length) {
                s->pos++;
                ch = [s->input characterAtIndex:s->pos];
                switch (ch) {
                    case 'n': [buf appendString:@"\n"]; break;
                    case 't': [buf appendString:@"\t"]; break;
                    case '\\': [buf appendString:@"\\"]; break;
                    case '\'': [buf appendString:@"'"]; break;
                    case '"': [buf appendString:@"\""]; break;
                    default: [buf appendFormat:@"%C", ch]; break;
                }
                s->pos++;
            } else {
                [buf appendFormat:@"%C", ch];
                s->pos++;
            }
        }
        if (s->pos >= s->input.length) _NSPREDICATE_RAISE(@"unterminated string literal");
        s->pos++;
        return [NSExpression expressionForConstantValue:buf];
    }

    /* Variable. */
    if (c == '$') {
        s->pos++;
        NSMutableString *name = [NSMutableString string];
        while (s->pos < s->input.length && _NSPsisIdentChar([s->input characterAtIndex:s->pos])) {
            [name appendFormat:@"%C", [s->input characterAtIndex:s->pos]];
            s->pos++;
        }
        if (name.length == 0) _NSPREDICATE_RAISE(@"empty variable name");
        return [NSExpression expressionForVariable:name];
    }

    /* Aggregate prefix: @sum.a / @count */
    if (c == '@') {
        s->pos++;
        NSMutableString *op = [NSMutableString string];
        while (s->pos < s->input.length && _NSPsisIdentChar([s->input characterAtIndex:s->pos])) {
            [op appendFormat:@"%C", [s->input characterAtIndex:s->pos]];
            s->pos++;
        }
        if (op.length == 0) _NSPREDICATE_RAISE(@"empty aggregate operator");
        NSString *rest = @"";
        _NSPSkipWhitespace(s);
        if (_NSPSPeek(s) == '.') {
            s->pos++;
            NSMutableString *path = [NSMutableString string];
            while (s->pos < s->input.length && (_NSPsisIdentChar([s->input characterAtIndex:s->pos]) || [s->input characterAtIndex:s->pos] == '.' || [s->input characterAtIndex:s->pos] == '@')) {
                [path appendFormat:@"%C", [s->input characterAtIndex:s->pos]];
                s->pos++;
            }
            rest = path;
        }
        NSString *funcName = [op stringByAppendingString:@":"];
        NSArray *aargs;
        if (rest.length) {
            aargs = @[[NSExpression expressionForKeyPath:rest]];
        } else if ([op isEqualToString:@"count"]) {
            aargs = @[[NSExpression expressionForEvaluatedObject]];
        } else {
            aargs = @[];
        }
        return [NSExpression expressionForFunction:funcName arguments:aargs];
    }

    /* Number literal. */
    if (c == '-' || (c >= '0' && c <= '9') || c == '.') {
        int sign = 1;
        NSUInteger start = s->pos;
        if (c == '-') {
            sign = -1;
            s->pos++;
            if (s->pos >= s->input.length || _NSPSPeek(s) < '0' || _NSPSPeek(s) > '9') {
                s->pos = start;
            }
        }
        BOOL isNumber = NO;
        if (s->pos < s->input.length) {
            unichar d = _NSPSPeek(s);
            if ((d >= '0' && d <= '9') || d == '.') isNumber = YES;
        }
        if (!isNumber) {
            s->pos = start;
        } else {
            BOOL anyDigit = NO;
            BOOL isFloating = NO;
            long long ival = 0;
            double frac = 0.0;
            while (s->pos < s->input.length) {
                unichar d = _NSPSPeek(s);
                if (d >= '0' && d <= '9') {
                    ival = ival * 10 + (long long)(d - '0');
                    anyDigit = YES;
                    s->pos++;
                } else break;
            }
            if (_NSPSPeek(s) == '.') {
                isFloating = YES;
                s->pos++;
                double scale = 0.1;
                while (s->pos < s->input.length) {
                    unichar d = _NSPSPeek(s);
                    if (d >= '0' && d <= '9') {
                        frac += (double)(d - '0') * scale;
                        scale *= 0.1;
                        anyDigit = YES;
                        s->pos++;
                    } else break;
                }
            }
            long long expn = 0;
            unichar e = _NSPSPeek(s);
            if (anyDigit && (e == 'e' || e == 'E')) {
                isFloating = YES;
                s->pos++;
                int esign = 1;
                if (_NSPSPeek(s) == '-') { esign = -1; s->pos++; }
                else if (_NSPSPeek(s) == '+') { s->pos++; }
                while (s->pos < s->input.length) {
                    unichar d = _NSPSPeek(s);
                    if (d >= '0' && d <= '9') { expn = expn * 10 + (long long)(d - '0'); s->pos++; }
                    else break;
                }
                expn *= esign;
            }
            if (!anyDigit) {
                s->pos = start;
            } else if (isFloating) {
                double dv = ((double)ival + frac) * (double)sign;
                if (expn) dv *= pow(10.0, (double)expn);
                return [NSExpression expressionForConstantValue:@(dv)];
            } else {
                long long iv = ival * (long long)sign;
                return [NSExpression expressionForConstantValue:@(iv)];
            }
        }
    }

    /* Brace-delimited list: {e1, e2, ...} */
    if (c == '{') {
        NSMutableArray *items = [NSMutableArray array];
        s->pos++;
        _NSPSkipWhitespace(s);
        while (_NSPSPeek(s) != '}') {
            if (_NSPSPeek(s) == 0) _NSPREDICATE_RAISE(@"unterminated brace list");
            [items addObject:_NSParseValueExpression(s)];
            _NSPSkipWhitespace(s);
            if (_NSPSPeek(s) == ',') { s->pos++; _NSPSkipWhitespace(s); }
            else if (_NSPSPeek(s) != '}') _NSPREDICATE_RAISE(@"expected ',' or '}'");
        }
        s->pos++;
        return [NSExpression expressionForAggregate:items];
    }

    /* Keywords. */
    if (_NSPSKeyword(s, @"TRUE") || _NSPSKeyword(s, @"YES")) return [NSExpression expressionForConstantValue:@(1)];
    if (_NSPSKeyword(s, @"FALSE") || _NSPSKeyword(s, @"NO")) return [NSExpression expressionForConstantValue:@(0)];

    /* Identifier / keypath / function call. */
    NSMutableString *ident = [NSMutableString string];
    while (s->pos < s->input.length && _NSPsisIdentChar([s->input characterAtIndex:s->pos])) {
        [ident appendFormat:@"%C", [s->input characterAtIndex:s->pos]];
        s->pos++;
    }
    if (ident.length == 0) _NSPREDICATE_RAISE(@"unexpected character");

    if ([ident isEqualToString:@"nil"] || [ident isEqualToString:@"NULL"] || [ident isEqualToString:@"null"]) {
        return [NSExpression expressionForConstantValue:nil];
    }

    _NSPSkipWhitespace(s);
    unichar after = _NSPSPeek(s);

    /* Function call: name:(a, b, ...) or FUNCTION(collection, 'sel:', ...) */
    if (after == '(' || after == ':') {
        NSMutableString *funcName = [[NSMutableString alloc] initWithString:ident];
        if (after == ':') {
            while (s->pos < s->input.length) {
                unichar ch = [s->input characterAtIndex:s->pos];
                if (_NSPsisIdentChar(ch) || ch == ':') {
                    [funcName appendFormat:@"%C", ch];
                    s->pos++;
                } else break;
            }
        } else {
            [funcName appendString:@":"];
        }
        _NSPSkipWhitespace(s);
        if (!_NSPSymbol(s, @"(")) _NSPREDICATE_RAISE(@"expected '(' after function name");
        NSMutableArray *args = [NSMutableArray array];
        _NSPSkipWhitespace(s);
        while (_NSPSPeek(s) != ')') {
            if (_NSPSPeek(s) == 0) _NSPREDICATE_RAISE(@"unterminated function call");
            [args addObject:_NSParseValueExpression(s)];
            _NSPSkipWhitespace(s);
            if (_NSPSPeek(s) == ',') { s->pos++; _NSPSkipWhitespace(s); }
            else break;
        }
        if (!_NSPSymbol(s, @")")) _NSPREDICATE_RAISE(@"expected ')' after function arguments");
        NSExpression *target = nil;
        NSArray *params = args;
        /* FUNCTION(collection, 'sel:', a, b) */
        if ([funcName isEqualToString:@"FUNCTION:"] || [funcName isEqualToString:@"function:"]) {
            if (args.count < 2 || ![args[1] isKindOfClass:[NSExpression class]]) _NSPREDICATE_RAISE(@"invalid FUNCTION()");
            NSExpression *col = args[0];
            NSExpression *selExpr = args[1];
            id selVal = [selExpr constantValue];
            if (![selVal isKindOfClass:[NSString class]]) _NSPREDICATE_RAISE(@"invalid FUNCTION() selector");
            target = col;
            funcName = [[NSMutableString alloc] initWithString:selVal];
            NSMutableArray *sub = [NSMutableArray array];
            for (NSUInteger i = 2; i < args.count; i++) [sub addObject:args[i]];
            params = sub;
        }
        if (target) {
            return [NSExpression expressionForFunction:target selectorName:funcName arguments:params];
        }
        return [NSExpression expressionForFunction:funcName arguments:params];
    }

    /* Plain key path. */
    NSMutableString *path = [[NSMutableString alloc] initWithString:ident];
    while (s->pos < s->input.length) {
        unichar d = [s->input characterAtIndex:s->pos];
        if (_NSPsisIdentChar(d) || d == '.' || d == '@') {
            [path appendFormat:@"%C", d];
            s->pos++;
        } else break;
    }
    return [NSExpression expressionForKeyPath:path];
}

static NSExpression *_NSParseMultiplicative(_NSPredicateStream *s) {
    NSExpression *left = _NSParsePrimary(s);
    _NSPSkipWhitespace(s);
    for (;;) {
        unichar c = _NSPSPeek(s);
        if (c == '*') {
            s->pos++;
            NSExpression *right = _NSParsePrimary(s);
            left = [NSExpression expressionForFunction:@"multiply:by:" arguments:@[left, right]];
        } else if (c == '/') {
            s->pos++;
            NSExpression *right = _NSParsePrimary(s);
            left = [NSExpression expressionForFunction:@"divide:by:" arguments:@[left, right]];
        } else {
            break;
        }
        _NSPSkipWhitespace(s);
    }
    return left;
}

static NSExpression *_NSParseValueExpression(_NSPredicateStream *s) {
    NSExpression *left = _NSParseMultiplicative(s);
    _NSPSkipWhitespace(s);
    for (;;) {
        unichar c = _NSPSPeek(s);
        if (c == '+') {
            s->pos++;
            NSExpression *right = _NSParseMultiplicative(s);
            left = [NSExpression expressionForFunction:@"add:to:" arguments:@[left, right]];
        } else if (c == '-') {
            s->pos++;
            NSExpression *right = _NSParseMultiplicative(s);
            left = [NSExpression expressionForFunction:@"from:subtract:" arguments:@[left, right]];
        } else {
            break;
        }
        _NSPSkipWhitespace(s);
    }
    return left;
}

/* Parse one comparison / modifier group, or a compound part. */
static NSPredicate *_NSParsePredicatePart(_NSPredicateStream *s);

static NSPredicate *_NSParseComparison(_NSPredicateStream *s) {
    _NSPSkipWhitespace(s);

    /* Grouped predicate: '(' ... ')' — trial parse with backtrack. */
    if (_NSPSPeek(s) == '(') {
        NSUInteger saved = s->pos;
        NSArray *savedArgs = s->args;
        _NSPredicateStream trial = *s;
        trial.pos++;
        @try {
            NSPredicate *inner = _NSParsePredicatePart(&trial);
            _NSPSkipWhitespace(&trial);
            if (_NSPSPeek(&trial) == ')') {
                trial.pos++;
                *s = trial;
                return inner;
            }
        } @catch (NSException *e) {
        }
        s->pos = saved;
        s->args = savedArgs;
    }

    NSComparisonPredicateModifier modifier = NSDirectPredicateModifier;
    BOOL negateNone = NO;
    _NSPSkipWhitespace(s);
    if (_NSPSKeyword(s, @"ANY")) modifier = NSAnyPredicateModifier;
    else if (_NSPSKeyword(s, @"ALL")) modifier = NSAllPredicateModifier;
    else if (_NSPSKeyword(s, @"NONE")) { modifier = NSAnyPredicateModifier; negateNone = YES; }

    _NSPSkipWhitespace(s);
    NSExpression *lhs = _NSParseValueExpression(s);
    _NSPSkipWhitespace(s);

    NSPredicateOperatorType op = 0;
    NSComparisonPredicateOptions options = 0;
    BOOL haveOp = NO;

    unichar c = _NSPSPeek(s);
    if (c == '=') {
        if (_NSPSymbol(s, @"==") || _NSPSymbol(s, @"=")) { op = NSEqualToPredicateOperatorType; haveOp = YES; }
    } else if (c == '!') {
        if (_NSPSymbol(s, @"!=")) { op = NSNotEqualToPredicateOperatorType; haveOp = YES; }
    } else if (c == '<') {
        if (_NSPSymbol(s, @"<=") || _NSPSymbol(s, @"=<")) { op = NSLessThanOrEqualToPredicateOperatorType; haveOp = YES; }
        else if (_NSPSymbol(s, @"<>")) { op = NSNotEqualToPredicateOperatorType; haveOp = YES; }
        else if (_NSPSymbol(s, @"<")) { op = NSLessThanPredicateOperatorType; haveOp = YES; }
    } else if (c == '>') {
        if (_NSPSymbol(s, @">=") || _NSPSymbol(s, @"=>")) { op = NSGreaterThanOrEqualToPredicateOperatorType; haveOp = YES; }
        else if (_NSPSymbol(s, @">")) { op = NSGreaterThanPredicateOperatorType; haveOp = YES; }
    } else if (_NSPSKeyword(s, @"BETWEEN")) { op = NSBetweenPredicateOperatorType; haveOp = YES; }
    else if (_NSPSKeyword(s, @"IN")) { op = NSInPredicateOperatorType; haveOp = YES; }
    else if (_NSPSKeyword(s, @"MATCHES")) { op = NSMatchesPredicateOperatorType; haveOp = YES; }
    else if (_NSPSKeyword(s, @"LIKE")) { op = NSLikePredicateOperatorType; haveOp = YES; }
    else if (_NSPSKeyword(s, @"BEGINSWITH")) { op = NSBeginsWithPredicateOperatorType; haveOp = YES; }
    else if (_NSPSKeyword(s, @"ENDSWITH")) { op = NSEndsWithPredicateOperatorType; haveOp = YES; }
    else if (_NSPSKeyword(s, @"CONTAINS")) { op = NSContainsPredicateOperatorType; haveOp = YES; }

    if (haveOp && op >= NSMatchesPredicateOperatorType && op <= NSContainsPredicateOperatorType) {
        _NSPSkipWhitespace(s);
        if (_NSPSPeek(s) == '[') {
            s->pos++;
            NSMutableString *flags = [NSMutableString string];
            while (s->pos < s->input.length && _NSPSPeek(s) != ']') {
                [flags appendFormat:@"%C", _NSPSPeek(s)];
                s->pos++;
            }
            if (_NSPSPeek(s) != ']') _NSPREDICATE_RAISE(@"unterminated modifier flags");
            s->pos++;
            for (NSUInteger i = 0; i < flags.length; i++) {
                unichar f = [flags characterAtIndex:i];
                if (f == 'c' || f == 'C') options |= NSCaseInsensitivePredicateOption;
                if (f == 'd' || f == 'D') options |= NSDiacriticInsensitivePredicateOption;
            }
        }
    }

    if (!haveOp) {
        _NSPREDICATE_RAISE(@"operator expected");
    }

    _NSPSkipWhitespace(s);
    NSExpression *rhs = _NSParseValueExpression(s);

    NSPredicate *p = [NSComparisonPredicate predicateWithLeftExpression:lhs rightExpression:rhs modifier:modifier type:op options:options];
    if (negateNone) {
        p = [NSCompoundPredicate notPredicateWithSubpredicate:p];
    }
    return p;
}
static NSPredicate *_NSParseNot(_NSPredicateStream *s);

static NSPredicate *_NSParseAnd(_NSPredicateStream *s) {
    NSPredicate *left = _NSParseNot(s);
    _NSPSkipWhitespace(s);
    while (_NSPSKeyword(s, @"AND") || _NSPSymbol(s, @"&&")) {
        NSPredicate *right = _NSParseNot(s);
        left = [NSCompoundPredicate andPredicateWithSubpredicates:@[left, right]];
        _NSPSkipWhitespace(s);
    }
    return left;
}

static NSPredicate *_NSParseOr(_NSPredicateStream *s) {
    NSPredicate *left = _NSParseAnd(s);
    _NSPSkipWhitespace(s);
    while (_NSPSKeyword(s, @"OR") || _NSPSymbol(s, @"||")) {
        NSPredicate *right = _NSParseAnd(s);
        left = [NSCompoundPredicate orPredicateWithSubpredicates:@[left, right]];
        _NSPSkipWhitespace(s);
    }
    return left;
}

static NSPredicate *_NSParseNot(_NSPredicateStream *s) {
    _NSPSkipWhitespace(s);
    if (_NSPSKeyword(s, @"NOT") || _NSPSKeyword(s, @"!") || _NSPSymbol(s, @"!")) {
        NSPredicate *sub = _NSParseNot(s);
        return [NSCompoundPredicate notPredicateWithSubpredicate:sub];
    }
    if (_NSPSKeyword(s, @"TRUEPREDICATE")) {
        return [NSPredicate predicateWithValue:YES];
    }
    if (_NSPSKeyword(s, @"FALSEPREDICATE")) {
        return [NSPredicate predicateWithValue:NO];
    }
    return _NSParseComparison(s);
}

static NSPredicate *_NSParsePredicatePart(_NSPredicateStream *s) {
    return _NSParseOr(s);
}

static void _NSParseCheckEnd(_NSPredicateStream *s) {
    _NSPSkipWhitespace(s);
    if (s->pos < s->input.length && _NSPSPeek(s) != ')') {
        NSUInteger p = s->pos;
        if ([s->input characterAtIndex:p] == 0) return;
        _NSPREDICATE_RAISE(@"unexpected trailing characters");
    }
}

NSArray *_NSPredicateCollectArguments(NSString *format, va_list args) {
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < format.length; i++) {
        if ([format characterAtIndex:i] == '%' && i + 1 < format.length) {
            unichar n = [format characterAtIndex:i + 1];
            if (n == '@' || n == 'K') count++;
        }
    }
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        id v = va_arg(args, id);
        [arr addObject:v ?: [NSNull null]];
    }
    return arr;
}

static NSPredicate *_NSPredicateParseFormatString(NSString *format, NSArray *args) {
    _NSPredicateStream s;
    s.input = format;
    s.pos = 0;
    s.args = args ? [args copy] : nil;
    NSPredicate *p = nil;
    @try {
        p = _NSParsePredicatePart(&s);
        _NSParseCheckEnd(&s);
    } @catch (NSException *e) {
        @throw;
    }
    return p;
}

/* ------------------------------------------------------------------ */
/*  NSExpression                                                       */
/* ------------------------------------------------------------------ */

@interface NSExpression () {
@private
    id _constantValue;
    NSString *_keyPath;
    NSString *_variable;
    NSString *_function;
    NSExpression *_targetExpression;
    NSExpression *_rightExpression;
    NSExpression *_trueExpression;
    NSExpression *_falseExpression;
    NSArray *_arguments;
    id _collection;
    NSPredicate *_predicate;
    id (^_exprBlock)(id, NSArray *, NSMutableDictionary *);
}

@end

@implementation NSExpression

+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat argumentArray:(NSArray *)arguments {
    return _NSPredicateParseExpressionFormat(expressionFormat, arguments);
}

+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat, ... {
    va_list args;
    va_start(args, expressionFormat);
    NSExpression *e = [NSExpression expressionWithFormat:expressionFormat arguments:args];
    va_end(args);
    return e;
}

+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat arguments:(va_list)argList {
    if (expressionFormat == nil) {
        [NSException raise:NSInvalidArgumentException format:@"expressionWithFormat: got nil format"];
    }
    _NSPredicateStream s;
    s.input = expressionFormat;
    s.pos = 0;
    s.args = _NSPredicateCollectArguments(expressionFormat, argList);
    NSExpression *e = _NSParseValueExpression(&s);
    _NSParseCheckEnd(&s);
    return e;
}

+ (NSExpression *)expressionForConstantValue:(id)obj {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSConstantValueExpressionType];
    e->_constantValue = obj;
    return e;
}

+ (NSExpression *)expressionForEvaluatedObject {
    return [[NSExpression alloc] initWithExpressionType:NSEvaluatedObjectExpressionType];
}

+ (NSExpression *)expressionForVariable:(NSString *)string {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSVariableExpressionType];
    e->_variable = [string copy];
    return e;
}

+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSKeyPathExpressionType];
    e->_keyPath = [keyPath copy];
    return e;
}

+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSFunctionExpressionType];
    e->_function = [name copy];
    e->_arguments = [parameters copy];
    return e;
}

+ (NSExpression *)expressionForAggregate:(NSArray *)subexpressions {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSAggregateExpressionType];
    e->_collection = [subexpressions copy];
    return e;
}

+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSUnionSetExpressionType];
    e->_targetExpression = left;
    e->_rightExpression = right;
    return e;
}

+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSIntersectSetExpressionType];
    e->_targetExpression = left;
    e->_rightExpression = right;
    return e;
}

+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSMinusSetExpressionType];
    e->_targetExpression = left;
    e->_rightExpression = right;
    return e;
}

+ (NSExpression *)expressionForSubquery:(NSExpression *)expression usingIteratorVariable:(NSString *)variable predicate:(NSPredicate *)predicate {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSSubqueryExpressionType];
    e->_collection = expression;
    e->_variable = [variable copy];
    e->_predicate = predicate;
    return e;
}

+ (NSExpression *)expressionForFunction:(NSExpression *)target selectorName:(NSString *)name arguments:(NSArray *)parameters {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSFunctionExpressionType];
    e->_function = [name copy];
    e->_targetExpression = target;
    e->_arguments = [parameters copy];
    return e;
}

+ (NSExpression *)expressionForAnyKey {
    return [[NSExpression alloc] initWithExpressionType:NSAnyKeyExpressionType];
}

+ (NSExpression *)expressionForBlock:(id (^)(id, NSArray *, NSMutableDictionary *))block arguments:(NSArray *)arguments {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSBlockExpressionType];
    e->_exprBlock = block;
    e->_arguments = [arguments copy];
    return e;
}

+ (NSExpression *)expressionForConditional:(NSPredicate *)predicate trueExpression:(NSExpression *)t falseExpression:(NSExpression *)f {
    NSExpression *e = [[NSExpression alloc] initWithExpressionType:NSConditionalExpressionType];
    e->_predicate = predicate;
    e->_trueExpression = t;
    e->_falseExpression = f;
    return e;
}

- (instancetype)init {
    return [self initWithExpressionType:NSConstantValueExpressionType];
}

- (instancetype)initWithExpressionType:(NSExpressionType)type {
    if ((self = [super init])) {
        _expressionType = type;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    if (self = [super init]) {
        _expressionType = (NSExpressionType)[coder decodeIntegerForKey:@"NS._expressionType"];
        _expressionFlags._evaluationBlocked = 1;
        switch (_expressionType) {
            case NSConstantValueExpressionType:
                _constantValue = [coder decodeObjectForKey:@"NS._constantValue"];
                break;
            case NSEvaluatedObjectExpressionType:
                break;
            case NSVariableExpressionType:
                _variable = [[coder decodeObjectForKey:@"NS._variable"] copy];
                break;
            case NSKeyPathExpressionType:
                _keyPath = [[coder decodeObjectForKey:@"NS._keyPath"] copy];
                break;
            case NSFunctionExpressionType:
                _function = [[coder decodeObjectForKey:@"NS._function"] copy];
                _targetExpression = [coder decodeObjectForKey:@"NS._targetExpression"];
                _arguments = [coder decodeObjectForKey:@"NS._arguments"];
                break;
            case NSUnionSetExpressionType:
            case NSIntersectSetExpressionType:
            case NSMinusSetExpressionType:
                _targetExpression = [coder decodeObjectForKey:@"NS._leftExpression"];
                _rightExpression = [coder decodeObjectForKey:@"NS._rightExpression"];
                break;
            case NSSubqueryExpressionType:
                _collection = [coder decodeObjectForKey:@"NS._collection"];
                _variable = [[coder decodeObjectForKey:@"NS._variable"] copy];
                _predicate = [coder decodeObjectForKey:@"NS._predicate"];
                break;
            case NSAggregateExpressionType:
                _collection = [coder decodeObjectForKey:@"NS._collection"];
                break;
            case NSAnyKeyExpressionType:
                break;
            case NSBlockExpressionType:
                _arguments = [coder decodeObjectForKey:@"NS._arguments"];
                break;
            case NSConditionalExpressionType:
                _predicate = [coder decodeObjectForKey:@"NS._predicate"];
                _trueExpression = [coder decodeObjectForKey:@"NS._trueExpression"];
                _falseExpression = [coder decodeObjectForKey:@"NS._falseExpression"];
                break;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        [self doesNotRecognizeSelector:_cmd];
    }
    [coder encodeInteger:(NSInteger)_expressionType forKey:@"NS._expressionType"];
    switch (_expressionType) {
        case NSConstantValueExpressionType:
            [coder encodeObject:_constantValue forKey:@"NS._constantValue"];
            break;
        case NSEvaluatedObjectExpressionType:
            break;
        case NSVariableExpressionType:
            [coder encodeObject:_variable forKey:@"NS._variable"];
            break;
        case NSKeyPathExpressionType:
            [coder encodeObject:_keyPath forKey:@"NS._keyPath"];
            break;
        case NSFunctionExpressionType:
            [coder encodeObject:_function forKey:@"NS._function"];
            if (_targetExpression) [coder encodeObject:_targetExpression forKey:@"NS._targetExpression"];
            if (_arguments) [coder encodeObject:_arguments forKey:@"NS._arguments"];
            break;
        case NSUnionSetExpressionType:
        case NSIntersectSetExpressionType:
        case NSMinusSetExpressionType:
            [coder encodeObject:_targetExpression forKey:@"NS._leftExpression"];
            [coder encodeObject:_rightExpression forKey:@"NS._rightExpression"];
            break;
        case NSSubqueryExpressionType:
            [coder encodeObject:_collection forKey:@"NS._collection"];
            [coder encodeObject:_variable forKey:@"NS._variable"];
            [coder encodeObject:_predicate forKey:@"NS._predicate"];
            break;
        case NSAggregateExpressionType:
            [coder encodeObject:_collection forKey:@"NS._collection"];
            break;
        case NSAnyKeyExpressionType:
            break;
        case NSBlockExpressionType:
            if (_arguments) [coder encodeObject:_arguments forKey:@"NS._arguments"];
            break;
        case NSConditionalExpressionType:
            [coder encodeObject:_predicate forKey:@"NS._predicate"];
            [coder encodeObject:_trueExpression forKey:@"NS._trueExpression"];
            [coder encodeObject:_falseExpression forKey:@"NS._falseExpression"];
            break;
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    NSExpression *copy = [[NSExpression alloc] initWithExpressionType:_expressionType];
    copy->_constantValue = _constantValue;
    copy->_keyPath = [_keyPath copy];
    copy->_variable = [_variable copy];
    copy->_function = [_function copy];
    copy->_targetExpression = [_targetExpression copy];
    copy->_rightExpression = [_rightExpression copy];
    copy->_trueExpression = [_trueExpression copy];
    copy->_falseExpression = [_falseExpression copy];
    copy->_arguments = [_arguments copy];
    copy->_collection = [_collection copy];
    copy->_predicate = [_predicate copy];
    copy->_exprBlock = _exprBlock;
    copy->_expressionFlags = _expressionFlags;
    return copy;
}

- (void)allowEvaluation {
    _expressionFlags._evaluationBlocked = 0;
}

- (NSExpressionType)expressionType {
    return _expressionType;
}

- (id)constantValue {
    if (_expressionType != NSConstantValueExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return constantValue for expression type %lu", (unsigned long)_expressionType];
    }
    return _constantValue;
}

- (NSString *)keyPath {
    if (_expressionType != NSKeyPathExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return keyPath for expression type %lu", (unsigned long)_expressionType];
    }
    return _keyPath;
}

- (NSString *)function {
    if (_expressionType != NSFunctionExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return function for expression type %lu", (unsigned long)_expressionType];
    }
    return _function;
}

- (NSString *)variable {
    if (_expressionType != NSVariableExpressionType && _expressionType != NSSubqueryExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return variable for expression type %lu", (unsigned long)_expressionType];
    }
    return _variable;
}

- (NSExpression *)operand {
    switch (_expressionType) {
        case NSFunctionExpressionType:
            return _targetExpression;
        case NSSubqueryExpressionType:
            return _collection;
        default:
            [NSException raise:NSInvalidArgumentException format:@"Can't return operand for expression type %lu", (unsigned long)_expressionType];
            break;
    }
    return nil;
}

- (NSArray *)arguments {
    switch (_expressionType) {
        case NSFunctionExpressionType:
        case NSBlockExpressionType:
            return _arguments;
        default:
            [NSException raise:NSInvalidArgumentException format:@"Can't return arguments for expression type %lu", (unsigned long)_expressionType];
            break;
    }
    return nil;
}

- (id)collection {
    if (_expressionType != NSAggregateExpressionType && _expressionType != NSSubqueryExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return collection for expression type %lu", (unsigned long)_expressionType];
    }
    return _collection;
}

- (NSPredicate *)predicate {
    if (_expressionType != NSSubqueryExpressionType && _expressionType != NSConditionalExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return predicate for expression type %lu", (unsigned long)_expressionType];
    }
    return _predicate;
}

- (NSExpression *)leftExpression {
    if (_expressionType != NSUnionSetExpressionType && _expressionType != NSIntersectSetExpressionType && _expressionType != NSMinusSetExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return leftExpression for expression type %lu", (unsigned long)_expressionType];
    }
    return _targetExpression;
}

- (NSExpression *)rightExpression {
    if (_expressionType != NSUnionSetExpressionType && _expressionType != NSIntersectSetExpressionType && _expressionType != NSMinusSetExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return rightExpression for expression type %lu", (unsigned long)_expressionType];
    }
    return _rightExpression;
}

- (NSExpression *)trueExpression {
    if (_expressionType != NSConditionalExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return trueExpression for expression type %lu", (unsigned long)_expressionType];
    }
    return _trueExpression;
}

- (NSExpression *)falseExpression {
    if (_expressionType != NSConditionalExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return falseExpression for expression type %lu", (unsigned long)_expressionType];
    }
    return _falseExpression;
}

- (id (^)(id, NSArray *, NSMutableDictionary *))expressionBlock {
    if (_expressionType != NSBlockExpressionType) {
        [NSException raise:NSInvalidArgumentException format:@"Can't return expressionBlock for expression type %lu", (unsigned long)_expressionType];
    }
    return _exprBlock;
}

static NSNumber *_NSExpressionTwoArgArith(NSString *name, NSArray *values) {
    if (values.count < 2) return nil;
    double a = [values[0] isKindOfClass:[NSNumber class]] ? [values[0] doubleValue] : 0;
    double b = [values[1] isKindOfClass:[NSNumber class]] ? [values[1] doubleValue] : 0;
    if ([name isEqualToString:@"add:to:"]) return @(a + b);
    if ([name isEqualToString:@"from:subtract:"]) return @(a - b);
    if ([name isEqualToString:@"multiply:by:"]) return @(a * b);
    if ([name isEqualToString:@"modulus:by:"]) return @(fmod(a, b));
    if ([name isEqualToString:@"raise:toPower:"]) return @(pow(a, b));
    if ([name isEqualToString:@"divide:by:"]) return (b != 0) ? @(a / b) : @0;
    /* Bitwise: operate on integer values. */
    long long ai = (long long)a;
    long long bi = (long long)b;
    if ([name isEqualToString:@"bitwiseAnd:with:"]) return @(ai & bi);
    if ([name isEqualToString:@"bitwiseOr:with:"]) return @(ai | bi);
    if ([name isEqualToString:@"bitwiseXor:with:"]) return @(ai ^ bi);
    if ([name isEqualToString:@"leftshift:by:"]) return @(ai << bi);
    if ([name isEqualToString:@"rightshift:by:"]) return @(ai >> bi);
    return nil;
}

static NSNumber *_NSExpressionUnaryArith(NSString *name, NSArray *values) {
    if (values.count != 1 || ![values[0] isKindOfClass:[NSNumber class]]) return nil;
    double v = [values[0] doubleValue];
    if ([name isEqualToString:@"sqrt:"]) return @(sqrt(v));
    if ([name isEqualToString:@"log:"]) return @(log10(v));
    if ([name isEqualToString:@"ln:"]) return @(log(v));
    if ([name isEqualToString:@"exp:"]) return @(exp(v));
    if ([name isEqualToString:@"floor:"]) return @(floor(v));
    if ([name isEqualToString:@"ceiling:"]) return @(ceil(v));
    if ([name isEqualToString:@"abs:"]) return @(fabs(v));
    if ([name isEqualToString:@"trunc:"]) return @(trunc(v));
    if ([name isEqualToString:@"onesComplement:"]) return @(~(long long)v);
    return nil;
}

static NSNumber *_NSExpressionAggregateNumber(NSString *name, NSArray *values) {
    NSMutableArray *nums = [NSMutableArray array];
    for (id v in values) {
        if ([v isKindOfClass:[NSNumber class]]) [nums addObject:v];
        else if (_NSPredicateIsCollection(v)) {
            NSArray *sub = _NSPredicateValuesForCollection(v, @"");
            for (id e in sub) if ([e isKindOfClass:[NSNumber class]]) [nums addObject:e];
        }
    }
    if (nums.count == 0) return nil;
    if ([name isEqualToString:@"count:"]) return @(nums.count);
    if ([name isEqualToString:@"sum:"]) {
        double t = 0;
        for (id n in nums) t += [n doubleValue];
        return @(t);
    }
    if ([name isEqualToString:@"average:"]) {
        double t = 0;
        for (id n in nums) t += [n doubleValue];
        return @(t / (double)nums.count);
    }
    if ([name isEqualToString:@"min:"]) {
        id best = nums[0];
        for (id n in nums) if ([n doubleValue] < [best doubleValue]) best = n;
        return best;
    }
    if ([name isEqualToString:@"max:"]) {
        id best = nums[0];
        for (id n in nums) if ([n doubleValue] > [best doubleValue]) best = n;
        return best;
    }
    if ([name isEqualToString:@"median:"]) {
        [nums sortUsingSelector:@selector(compare:)];
        NSUInteger mid = nums.count / 2;
        if (nums.count % 2) return nums[mid];
        double lo = [nums[mid - 1] doubleValue];
        double hi = [nums[mid] doubleValue];
        return @((lo + hi) / 2.0);
    }
    if ([name isEqualToString:@"stddev:"]) {
        double t = 0;
        for (id n in nums) t += [n doubleValue];
        double mean = t / (double)nums.count;
        double accum = 0;
        for (id n in nums) { double d = [n doubleValue] - mean; accum += d * d; }
        return @(sqrt(accum / (double)nums.count));
    }
    return nil;
}

- (id)_evaluateFunctionWithObject:(id)object context:(NSMutableDictionary *)context {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:_arguments.count];
    for (NSExpression *arg in _arguments) {
        [values addObject:[arg expressionValueWithObject:object context:context] ?: [NSNull null]];
    }
    NSString *fname = _function;

    if (_targetExpression) {
        SEL selector = NSSelectorFromString(_function);
        id target = [_targetExpression expressionValueWithObject:object context:context];
        if (target == nil || ![target respondsToSelector:selector]) {
            [NSException raise:NSInvalidArgumentException format:@"Unable to evaluate function '%@' on target: target is nil or does not respond to the selector", _function];
        }
        NSMutableArray *msgArgs = [NSMutableArray arrayWithCapacity:values.count];
        for (id v in values) {
            [msgArgs addObject:v == [NSNull null] ? nil : v];
        }
        switch (msgArgs.count) {
            case 0:
                return ((id (*)(id, SEL))objc_msgSend)(target, selector);
            case 1:
                return ((id (*)(id, SEL, id))objc_msgSend)(target, selector, msgArgs[0]);
            case 2:
                return ((id (*)(id, SEL, id, id))objc_msgSend)(target, selector, msgArgs[0], msgArgs[1]);
            case 3:
                return ((id (*)(id, SEL, id, id, id))objc_msgSend)(target, selector, msgArgs[0], msgArgs[1], msgArgs[2]);
            default:
                [NSException raise:NSInvalidArgumentException format:@"Unable to evaluate function '%@': too many arguments", _function];
                return nil;
        }
    }

    if ([fname hasSuffix:@":"]) {
        NSNumber *n = nil;
        if ((n = _NSExpressionUnaryArith(fname, values))) return n;
        if ((n = _NSExpressionTwoArgArith(fname, values))) return n;
        if ((n = _NSExpressionAggregateNumber(fname, values))) return n;
    }

    if ([fname isEqualToString:@"uppercase:"] && values.count == 1) {
        id v0 = values[0];
        if ([v0 isKindOfClass:[NSString class]]) return [(NSString *)v0 uppercaseString];
    }
    if ([fname isEqualToString:@"lowercase:"] && values.count == 1) {
        id v0 = values[0];
        if ([v0 isKindOfClass:[NSString class]]) return [(NSString *)v0 lowercaseString];
    }
    if ([fname isEqualToString:@"canonical:"] && values.count == 1) {
        return values[0] == [NSNull null] ? nil : values[0];
    }
    if ([fname isEqualToString:@"length:"] && values.count == 1) {
        id v0 = values[0];
        if ([v0 isKindOfClass:[NSString class]]) return @([(NSString *)v0 length]);
        if ([v0 isKindOfClass:[NSArray class]]) return @([(NSArray *)v0 count]);
    }
    if ([fname isEqualToString:@"uppercase:"]) {
        id v0 = values[0];
        if ([v0 isKindOfClass:[NSString class]]) return [(NSString *)v0 uppercaseString];
    }
    [NSException raise:NSInvalidArgumentException format:@"Unknown function '%@'", _function];
    return nil;
}

- (id)expressionValueWithObject:(id)object context:(NSMutableDictionary *)context {
    if (_expressionFlags._evaluationBlocked) {
        [NSException raise:NSGenericException format:@"This expression has not been allowed evaluation because it was created with a secure coding mechanism"];
    }
    switch (_expressionType) {
        case NSConstantValueExpressionType:
            return _constantValue;
        case NSEvaluatedObjectExpressionType:
            return object;
        case NSVariableExpressionType:
            return context[_variable];
        case NSKeyPathExpressionType:
            return _NSPredicateValueForKeyPath(object, _keyPath);
        case NSFunctionExpressionType:
            return [self _evaluateFunctionWithObject:object context:context];
        case NSUnionSetExpressionType:
        case NSIntersectSetExpressionType:
        case NSMinusSetExpressionType: {
            id l = [_targetExpression expressionValueWithObject:object context:context];
            id r = [_rightExpression expressionValueWithObject:object context:context];
            NSSet *ls = [l isKindOfClass:[NSSet class]] ? l : l ? [NSSet setWithObject:l] : [NSSet set];
            NSSet *rs = [r isKindOfClass:[NSSet class]] ? r : r ? [NSSet setWithObject:r] : [NSSet set];
            if (_expressionType == NSUnionSetExpressionType) return [ls setByAddingObjectsFromSet:rs];
            if (_expressionType == NSIntersectSetExpressionType) {
                NSMutableSet *m = [ls mutableCopy];
                [m intersectSet:rs];
                return m;
            }
            NSMutableSet *m = [ls mutableCopy];
            [m minusSet:rs];
            return m;
        }
        case NSSubqueryExpressionType: {
            id collection = [_collection expressionValueWithObject:object context:context];
            NSMutableArray *matches = [NSMutableArray array];
            _NSPredicateEnumerateCollection(collection, ^(id element) {
                if (_predicate) {
                    NSMutableDictionary *ctx = context ?: [NSMutableDictionary dictionary];
                    id saved = ctx[_variable];
                    ctx[_variable] = element;
                    BOOL r = [_predicate evaluateWithObject:element];
                    if (saved) ctx[_variable] = saved; else [ctx removeObjectForKey:_variable];
                    if (r) [matches addObject:element];
                }
            });
            if ([collection isKindOfClass:[NSSet class]]) return [NSSet setWithArray:matches];
            return matches;
        }
        case NSAggregateExpressionType: {
            NSMutableArray *vals = [NSMutableArray array];
            for (NSExpression *sub in _collection) {
                [vals addObject:[sub expressionValueWithObject:object context:context] ?: [NSNull null]];
            }
            return vals;
        }
        case NSAnyKeyExpressionType:
            [NSException raise:NSInvalidArgumentException format:@"AnyKey expression called for evaluation"];
            break;
        case NSBlockExpressionType: {
            NSMutableArray *vals = [NSMutableArray array];
            for (NSExpression *sub in _arguments) {
                [vals addObject:[sub expressionValueWithObject:object context:context] ?: [NSNull null]];
            }
            return _exprBlock ? _exprBlock(object, vals, context) : nil;
        }
        case NSConditionalExpressionType: {
            BOOL p = _predicate ? [_predicate evaluateWithObject:object] : NO;
            return [p ? _trueExpression : _falseExpression expressionValueWithObject:object context:context];
        }
    }
    return nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p expressionType=%lu>", NSStringFromClass([self class]), self, (unsigned long)_expressionType];
}

@end

static NSString *_NSPredicateJoinComponents(NSArray *parts, NSString *separator) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0;
    for (NSString *piece in parts) {
        if (i++ > 0) [out appendString:separator];
        [out appendString:piece];
    }
    return out;
}

/* Private description used to build canonical predicate format strings. */
@implementation NSExpression (_NSPredicateFormat)

- (NSString *)_NSPredicateDescription {
    switch (_expressionType) {
        case NSConstantValueExpressionType: {
            id v = _constantValue;
            if (v == nil) return @"nil";
            if ([v isKindOfClass:[NSNumber class]]) {
                double d = [v doubleValue];
                if (d == (long long)d && [v isEqual:@((long long)d)]) return [NSString stringWithFormat:@"%lld", (long long)d];
                return [NSString stringWithFormat:@"%g", d];
            }
            if ([v isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", v];
            if ([v isKindOfClass:[NSArray class]]) {
                NSMutableArray *parts = [NSMutableArray array];
                for (id e in (NSArray *)v) {
                    NSExpression *ee = [e isKindOfClass:[NSExpression class]] ? e : [NSExpression expressionForConstantValue:e];
                    [parts addObject:[ee _NSPredicateDescription]];
                }
                return [NSString stringWithFormat:@"{%@}", _NSPredicateJoinComponents(parts, @", ")];
            }
            return [v description];
        }
        case NSEvaluatedObjectExpressionType:
            return @"SELF";
        case NSVariableExpressionType:
            return [NSString stringWithFormat:@"$%@", _variable];
        case NSKeyPathExpressionType:
            return _keyPath;
        case NSFunctionExpressionType: {
            NSMutableArray *parts = [NSMutableArray array];
            if (_targetExpression) [parts addObject:[_targetExpression _NSPredicateDescription]];
            for (NSExpression *arg in _arguments) {
                [parts addObject:[arg _NSPredicateDescription]];
            }
            NSString *joined = parts.count ? _NSPredicateJoinComponents(parts, @", ") : @"";
            return [NSString stringWithFormat:@"%@(%@)", _function, joined];
        }
        case NSUnionSetExpressionType:
        case NSIntersectSetExpressionType:
        case NSMinusSetExpressionType: {
            NSString *op = @"UNION";
            if (_expressionType == NSIntersectSetExpressionType) op = @"INTERSECT";
            if (_expressionType == NSMinusSetExpressionType) op = @"MINUS";
            return [NSString stringWithFormat:@"%@(%@, %@)", op, [_targetExpression _NSPredicateDescription], [_rightExpression _NSPredicateDescription]];
        }
        case NSAggregateExpressionType: {
            NSMutableArray *parts = [NSMutableArray array];
            for (NSExpression *sub in _collection) [parts addObject:[sub _NSPredicateDescription]];
            return [NSString stringWithFormat:@"{%@}", _NSPredicateJoinComponents(parts, @", ")];
        }
        case NSSubqueryExpressionType:
            return [NSString stringWithFormat:@"SUBQUERY(%@, $%@, %@)", [_collection _NSPredicateDescription], _variable, [_predicate predicateFormat]];
        case NSBlockExpressionType:
            return @"BLOCK";
        case NSConditionalExpressionType: {
            return [NSString stringWithFormat:@"CONDITIONAL(%@, %@, %@)", [_predicate predicateFormat], [_trueExpression _NSPredicateDescription], [_falseExpression _NSPredicateDescription]];
        }
        case NSAnyKeyExpressionType:
            return @"ANYKEY";
    }
    return @"";
}

@end

static NSExpression *_NSPExpressionSubstitute(NSExpression *e, NSDictionary *bindings) {
    switch (e.expressionType) {
        case NSVariableExpressionType: {
            id value = [bindings objectForKey:[e variable]];
            if (value == nil) {
                [NSException raise:NSInvalidArgumentException format:@"Unable to substitute variable '%@' because it is not in the substitution dictionary", [e variable]];
            }
            return [NSExpression expressionForConstantValue:value];
        }
        case NSFunctionExpressionType: {
            NSArray *params = e.arguments ?: @[];
            NSMutableArray *outParams = [NSMutableArray arrayWithCapacity:params.count];
            for (NSExpression *p in params) {
                [outParams addObject:_NSPExpressionSubstitute(p, bindings)];
            }
            if (e.operand) {
                return [NSExpression expressionForFunction:_NSPExpressionSubstitute(e.operand, bindings) selectorName:e.function arguments:outParams];
            }
            return [NSExpression expressionForFunction:e.function arguments:outParams];
        }
        case NSAggregateExpressionType: {
            NSMutableArray *outItems = [NSMutableArray array];
            for (id item in e.collection) {
                if ([item isKindOfClass:[NSExpression class]]) {
                    [outItems addObject:_NSPExpressionSubstitute(item, bindings)];
                } else {
                    [outItems addObject:item];
                }
            }
            return [NSExpression expressionForAggregate:outItems];
        }
        case NSConditionalExpressionType: {
            NSPredicate *p = [[e predicate] predicateWithSubstitutionVariables:bindings];
            NSExpression *t = _NSPExpressionSubstitute(e.trueExpression, bindings);
            NSExpression *f = _NSPExpressionSubstitute(e.falseExpression, bindings);
            return [NSExpression expressionForConditional:p trueExpression:t falseExpression:f];
        }
        case NSSubqueryExpressionType: {
            NSExpression *col = _NSPExpressionSubstitute(e.collection, bindings);
            NSPredicate *p = [[e predicate] predicateWithSubstitutionVariables:bindings];
            return [NSExpression expressionForSubquery:col usingIteratorVariable:e.variable predicate:p];
        }
        default:
            return e;
    }
}

NSExpression *_NSPredicateExpressionWithSubstitutions(NSExpression *e, NSDictionary *bindings) {
    if (e == nil || bindings == nil) return e;
    return _NSPExpressionSubstitute(e, bindings);
}

NSPredicate *_NSPredicateParseFormat(NSString *format, NSArray *args) {
    return _NSPredicateParseFormatString(format, args);
}

NSExpression *_NSPredicateParseExpressionFormat(NSString *format, NSArray *args) {
    _NSPredicateStream s;
    s.input = format;
    s.pos = 0;
    s.args = args ? [args copy] : nil;
    NSExpression *e = _NSParseValueExpression(&s);
    _NSParseCheckEnd(&s);
    return e;
}