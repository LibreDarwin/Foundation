/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import "NSDecimalNumber.h"
#import <Foundation/NSString.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <objc/runtime.h>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

NSString * const NSDecimalNumberExactnessException = @"NSDecimalNumberExactnessException";
NSString * const NSDecimalNumberOverflowException = @"NSDecimalNumberOverflowException";
NSString * const NSDecimalNumberUnderflowException = @"NSDecimalNumberUnderflowException";
NSString * const NSDecimalNumberDivideByZeroException = @"NSDecimalNumberDivideByZeroException";

static id <NSDecimalNumberBehaviors> __NSDecimalDefaultBehavior;

/* NSNumber -init mints a fresh CF number in place of the +alloc receiver, so
 * [super init] would hand back a CFNumber and drop the plain NSDecimalNumber
 * storage this class owns (mirrors how Apple's NSDecimalNumber stays a plain
 * object while NSNumber remains a cluster). Initialize via NSObject init,
 * which returns self untouched. */
static id __NSDecimalNumberSuperInit(id self) {
    SEL selector = @selector(init);
    IMP implementation = class_getMethodImplementation([NSObject class], selector);
    return ((id (*)(id, SEL))implementation)(self, selector);
}

#if __has_feature(objc_arc)
#define __NSDECIMAL_AUTORELEASE(object) (object)
#define __NSDECIMAL_RETAIN(object) (object)
#define __NSDECIMAL_RELEASE(object) ((void)0)
#else
#define __NSDECIMAL_AUTORELEASE(object) [(object) autorelease]
#define __NSDECIMAL_RETAIN(object) [(object) retain]
#define __NSDECIMAL_RELEASE(object) [(object) release]
#endif

static NSDecimal __NSDecimalFromString(NSString *string) {
    NSDecimal decimal = {0};
    const char *text = string == nil ? "0" : [string UTF8String];
    if (text == NULL) text = "0";
    BOOL negative = NO;
    if (*text == '-') { negative = YES; text++; }
    unsigned char digits[64] = {0};
    unsigned int count = 0;
    int exponent = 0;
    BOOL afterDecimal = NO;
    while (*text != 0 && *text != 'e' && *text != 'E') {
        if (*text == '.') { afterDecimal = YES; text++; continue; }
        if (*text >= '0' && *text <= '9') {
            if (count < sizeof(digits)) digits[count++] = (unsigned char)(*text - '0');
            if (afterDecimal) exponent--;
        }
        text++;
    }
    if (*text == 'e' || *text == 'E') exponent += (int)strtol(text + 1, NULL, 10);
    unsigned int first = 0;
    while (first < count && digits[first] == 0) first++;
    if (first == count) return decimal;
    count -= first;
    memmove(digits, digits + first, count);
    while (count != 0 && digits[count - 1] == 0) { count--; exponent++; }
    while (count > 38) { count--; exponent++; }
    unsigned short words[NSDecimalMaxSize] = {0};
    unsigned int wordCount = 0;
    for (unsigned int i = 0; i < count; i++) {
        unsigned int carry = digits[i];
        for (unsigned int j = 0; j < wordCount; j++) {
            unsigned int value = words[j] * 10U + carry;
            words[j] = (unsigned short)(value & 0xffffU);
            carry = value >> 16;
        }
        if (carry != 0) words[wordCount++] = (unsigned short)carry;
    }
    decimal._length = wordCount;
    for (unsigned int i = 0; i < wordCount; i++) decimal._mantissa[i] = words[i];
    decimal._exponent = exponent;
    decimal._isNegative = negative;
    decimal._isCompact = 1;
    return decimal;
}

static NSDecimalNumber *__NSDecimalResult(NSDecimal decimal) {
    return __NSDECIMAL_AUTORELEASE([[NSDecimalNumber alloc] initWithDecimal:decimal]);
}

static NSDecimalNumber *__NSDecimalResultWithBehavior(NSCalculationError error, id <NSDecimalNumberBehaviors> behavior, SEL operation, NSDecimalNumber *left, NSDecimalNumber *right, NSDecimal decimal) {
    NSDecimal result = decimal;
    if (error == NSCalculationNoError && behavior != nil && [behavior scale] != NSDecimalNoScale) {
        NSDecimal rounded;
        NSDecimalRound(&rounded, &result, [behavior scale], [behavior roundingMode]);
        result = rounded;
    }
    NSDecimalNumber *object = __NSDecimalResult(result);
    if (error == NSCalculationNoError || behavior == nil || ![(id)behavior respondsToSelector:@selector(exceptionDuringOperation:error:leftOperand:rightOperand:)]) return object;
    NSDecimalNumber *handled = [behavior exceptionDuringOperation:operation error:error leftOperand:left rightOperand:right];
    return handled == nil ? object : handled;
}

@implementation NSDecimalNumber

- (instancetype)initWithDecimal:(NSDecimal)decimal { self = __NSDecimalNumberSuperInit(self); if (self != nil) _decimal = decimal; return self; }
- (instancetype)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative { self = __NSDecimalNumberSuperInit(self); if (self != nil) { _decimal = (NSDecimal){0}; for (unsigned int i = 0; i < NSDecimalMaxSize && mantissa != 0; i++) { _decimal._mantissa[i] = (unsigned short)(mantissa & 0xffffU); mantissa >>= 16; _decimal._length++; } _decimal._exponent = exponent; _decimal._isNegative = negative; if (_decimal._length == 0 && !negative) _decimal._isNegative = NO; _decimal._isCompact = 1; if (_decimal._length != 0) NSDecimalCompact(&_decimal); } return self; }
- (instancetype)initWithString:(NSString *)string { return [self initWithDecimal:__NSDecimalFromString(string)]; }
- (instancetype)initWithString:(NSString *)string locale:(id)locale { (void)locale; return [self initWithString:string]; }

+ (instancetype)decimalNumberWithDecimal:(NSDecimal)decimal { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithDecimal:decimal]); }
+ (instancetype)decimalNumberWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithMantissa:mantissa exponent:exponent isNegative:negative]); }
+ (instancetype)decimalNumberWithString:(NSString *)string { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithString:string]); }
+ (instancetype)decimalNumberWithString:(NSString *)string locale:(id)locale { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithString:string locale:locale]); }
+ (instancetype)zero { return [self decimalNumberWithMantissa:0 exponent:0 isNegative:NO]; }
+ (instancetype)one { return [self decimalNumberWithMantissa:1 exponent:0 isNegative:NO]; }
+ (instancetype)minimumDecimalNumber {
    NSDecimal decimal = {0};
    for (unsigned int i = 0; i < NSDecimalMaxSize; i++) decimal._mantissa[i] = 0xffff;
    decimal._length = NSDecimalMaxSize;
    decimal._exponent = 127;
    decimal._isNegative = 1;
    decimal._isCompact = 1;
    return [self decimalNumberWithDecimal:decimal];
}
+ (instancetype)maximumDecimalNumber {
    NSDecimal decimal = {0};
    for (unsigned int i = 0; i < NSDecimalMaxSize; i++) decimal._mantissa[i] = 0xffff;
    decimal._length = NSDecimalMaxSize;
    decimal._exponent = 127;
    decimal._isCompact = 1;
    return [self decimalNumberWithDecimal:decimal];
}
+ (instancetype)notANumber { NSDecimal decimal = {0}; decimal._isNegative = 1; return [self decimalNumberWithDecimal:decimal]; }

+ (id <NSDecimalNumberBehaviors>)defaultBehavior { if (__NSDecimalDefaultBehavior == nil) __NSDecimalDefaultBehavior = [NSDecimalNumberHandler defaultDecimalNumberHandler]; return __NSDecimalDefaultBehavior; }
+ (void)setDefaultBehavior:(id <NSDecimalNumberBehaviors>)behavior {
    if (__NSDecimalDefaultBehavior == behavior) return;
    id <NSDecimalNumberBehaviors> retained = __NSDECIMAL_RETAIN((id)behavior);
    __NSDECIMAL_RELEASE((id)__NSDecimalDefaultBehavior);
    __NSDecimalDefaultBehavior = retained;
}

- (NSDecimal)decimalValue { return _decimal; }
- (NSComparisonResult)compare:(NSNumber *)number { if ([number isKindOfClass:[NSDecimalNumber class]]) { NSDecimal other = [(NSDecimalNumber *)number decimalValue]; return NSDecimalCompare(&_decimal, &other); } double left = [self doubleValue], right = [number doubleValue]; return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame; }
- (double)doubleValue { char *end = NULL; NSString *string = NSDecimalString(&_decimal, nil); return strtod([string UTF8String], &end); }
- (const char *)objCType { return @encode(double); }
- (NSString *)stringValue { return NSDecimalString(&_decimal, nil); }
- (NSString *)description { return [self stringValue]; }
- (NSString *)descriptionWithLocale:(NSDictionary *)locale { return NSDecimalString(&_decimal, locale); }

- (instancetype)decimalNumberByRoundingAccordingToBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result; NSDecimalRound(&result, &_decimal, [behavior scale], [behavior roundingMode]); return __NSDecimalResult(result); }
- (instancetype)decimalNumberByAdding:(NSDecimalNumber *)number { return [self decimalNumberByAdding:number withBehavior:nil]; }
- (instancetype)decimalNumberByAdding:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result; NSCalculationError error = NSDecimalAdd(&result, &_decimal, &number->_decimal, [behavior roundingMode]); return __NSDecimalResultWithBehavior(error, behavior, @selector(decimalNumberByAdding:), self, number, result); }
- (instancetype)decimalNumberBySubtracting:(NSDecimalNumber *)number { return [self decimalNumberBySubtracting:number withBehavior:nil]; }
- (instancetype)decimalNumberBySubtracting:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result; NSCalculationError error = NSDecimalSubtract(&result, &_decimal, &number->_decimal, [behavior roundingMode]); return __NSDecimalResultWithBehavior(error, behavior, @selector(decimalNumberBySubtracting:), self, number, result); }
- (instancetype)decimalNumberByMultiplyingBy:(NSDecimalNumber *)number { return [self decimalNumberByMultiplyingBy:number withBehavior:nil]; }
- (instancetype)decimalNumberByMultiplyingBy:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result; NSCalculationError error = NSDecimalMultiply(&result, &_decimal, &number->_decimal, [behavior roundingMode]); return __NSDecimalResultWithBehavior(error, behavior, @selector(decimalNumberByMultiplyingBy:), self, number, result); }
- (instancetype)decimalNumberByDividingBy:(NSDecimalNumber *)number { return [self decimalNumberByDividingBy:number withBehavior:nil]; }
- (instancetype)decimalNumberByDividingBy:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result = {0}; NSCalculationError error = NSDecimalDivide(&result, &_decimal, &number->_decimal, [behavior roundingMode]); return __NSDecimalResultWithBehavior(error, behavior, @selector(decimalNumberByDividingBy:), self, number, result); }
- (instancetype)decimalNumberByRaisingToPower:(NSUInteger)power { return [self decimalNumberByRaisingToPower:power withBehavior:nil]; }
- (instancetype)decimalNumberByRaisingToPower:(NSUInteger)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result; NSCalculationError error = NSDecimalPower(&result, &_decimal, power, [behavior roundingMode]); return __NSDecimalResultWithBehavior(error, behavior, @selector(decimalNumberByRaisingToPower:), self, nil, result); }
- (instancetype)decimalNumberByMultiplyingByPowerOf10:(short)power { return [self decimalNumberByMultiplyingByPowerOf10:power withBehavior:nil]; }
- (instancetype)decimalNumberByMultiplyingByPowerOf10:(short)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result = {0}; NSCalculationError error = NSDecimalMultiplyByPowerOf10(&result, &_decimal, power, [behavior roundingMode]); return __NSDecimalResultWithBehavior(error, behavior, @selector(decimalNumberByMultiplyingByPowerOf10:), self, nil, result); }

@end

@implementation NSDecimalNumberHandler
- (instancetype)initWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero {
    self = [super init];
    if (self != nil) {
        _scale = scale;
        _roundingMode = roundingMode;
        _raiseOnExactness = exact ? 1 : 0;
        _raiseOnOverflow = overflow ? 1 : 0;
        _raiseOnUnderflow = underflow ? 1 : 0;
        _raiseOnDivideByZero = divideByZero ? 1 : 0;
    }
    return self;
}
+ (instancetype)decimalNumberHandlerWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero {
    return __NSDECIMAL_AUTORELEASE([[self alloc] initWithRoundingMode:roundingMode scale:scale raiseOnExactness:exact raiseOnOverflow:overflow raiseOnUnderflow:underflow raiseOnDivideByZero:divideByZero]);
}
- (NSRoundingMode)roundingMode { return _roundingMode; }
- (short)scale { return _scale; }
- (BOOL)raiseOnExactness { return _raiseOnExactness ? YES : NO; }
- (BOOL)raiseOnOverflow { return _raiseOnOverflow ? YES : NO; }
- (BOOL)raiseOnUnderflow { return _raiseOnUnderflow ? YES : NO; }
- (BOOL)raiseOnDivideByZero { return _raiseOnDivideByZero ? YES : NO; }
+ (instancetype)defaultDecimalNumberHandler {
    static id defaultHandler = nil;
    if (defaultHandler == nil) defaultHandler = [[self alloc] initWithRoundingMode:NSRoundPlain scale:NSDecimalNoScale raiseOnExactness:NO raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    return defaultHandler;
}
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation error:(NSCalculationError)error leftOperand:(NSDecimalNumber *)leftOperand rightOperand:(NSDecimalNumber *)rightOperand {
    (void)operation;
    (void)leftOperand;
    (void)rightOperand;
    NSExceptionName name = NSDecimalNumberExactnessException;
    switch (error) {
        case NSCalculationUnderflow: if (!_raiseOnUnderflow) return nil; name = NSDecimalNumberUnderflowException; break;
        case NSCalculationOverflow: if (!_raiseOnOverflow) return nil; name = NSDecimalNumberOverflowException; break;
        case NSCalculationDivideByZero: if (!_raiseOnDivideByZero) return nil; name = NSDecimalNumberDivideByZeroException; break;
        case NSCalculationNoError: return nil;
        default: if (!_raiseOnExactness) return nil; break;
    }
    [NSException raise:name format:@"decimal operation %s failed", sel_getName(operation)];
    return nil;
}
@end
