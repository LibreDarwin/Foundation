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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

NSString * const NSDecimalNumberExactnessException = @"NSDecimalNumberExactnessException";
NSString * const NSDecimalNumberOverflowException = @"NSDecimalNumberOverflowException";
NSString * const NSDecimalNumberUnderflowException = @"NSDecimalNumberUnderflowException";
NSString * const NSDecimalNumberDivideByZeroException = @"NSDecimalNumberDivideByZeroException";

static id <NSDecimalNumberBehaviors> __NSDecimalDefaultBehavior;

#if __has_feature(objc_arc)
#define __NSDECIMAL_AUTORELEASE(object) (object)
#else
#define __NSDECIMAL_AUTORELEASE(object) [(object) autorelease]
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

@implementation NSDecimalNumber

- (instancetype)initWithDecimal:(NSDecimal)decimal { self = [super init]; if (self != nil) _decimal = decimal; return self; }
- (instancetype)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative { self = [super init]; if (self != nil) { _decimal = (NSDecimal){0}; for (unsigned int i = 0; i < NSDecimalMaxSize && mantissa != 0; i++) { _decimal._mantissa[i] = (unsigned short)(mantissa & 0xffffU); mantissa >>= 16; _decimal._length++; } _decimal._exponent = exponent; _decimal._isNegative = negative && _decimal._length != 0; _decimal._isCompact = 1; NSDecimalCompact(&_decimal); } return self; }
- (instancetype)initWithString:(NSString *)string { return [self initWithDecimal:__NSDecimalFromString(string)]; }
- (instancetype)initWithString:(NSString *)string locale:(id)locale { (void)locale; return [self initWithString:string]; }

+ (instancetype)decimalNumberWithDecimal:(NSDecimal)decimal { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithDecimal:decimal]); }
+ (instancetype)decimalNumberWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithMantissa:mantissa exponent:exponent isNegative:negative]); }
+ (instancetype)decimalNumberWithString:(NSString *)string { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithString:string]); }
+ (instancetype)decimalNumberWithString:(NSString *)string locale:(id)locale { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithString:string locale:locale]); }
+ (instancetype)zero { return [self decimalNumberWithMantissa:0 exponent:0 isNegative:NO]; }
+ (instancetype)one { return [self decimalNumberWithMantissa:1 exponent:0 isNegative:NO]; }
+ (instancetype)minimumDecimalNumber { return [self decimalNumberWithMantissa:1 exponent:SCHAR_MIN isNegative:NO]; }
+ (instancetype)maximumDecimalNumber { return [self decimalNumberWithMantissa:ULLONG_MAX exponent:SCHAR_MAX isNegative:NO]; }
+ (instancetype)notANumber { NSDecimal decimal = {0}; decimal._isNegative = 1; return [self decimalNumberWithDecimal:decimal]; }

+ (id <NSDecimalNumberBehaviors>)defaultBehavior { if (__NSDecimalDefaultBehavior == nil) __NSDecimalDefaultBehavior = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundPlain scale:NSDecimalNoScale]; return __NSDecimalDefaultBehavior; }
+ (void)setDefaultBehavior:(id <NSDecimalNumberBehaviors>)behavior { __NSDecimalDefaultBehavior = behavior; }

- (NSDecimal)decimalValue { return _decimal; }
- (NSComparisonResult)compare:(NSNumber *)number { if ([number isKindOfClass:[NSDecimalNumber class]]) { NSDecimal other = [(NSDecimalNumber *)number decimalValue]; return NSDecimalCompare(&_decimal, &other); } double left = [self doubleValue], right = [number doubleValue]; return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame; }
- (double)doubleValue { char *end = NULL; NSString *string = NSDecimalString(&_decimal, nil); return strtod([string UTF8String], &end); }
- (const char *)objCType { return @encode(double); }
- (NSString *)stringValue { return NSDecimalString(&_decimal, nil); }
- (NSString *)description { return [self stringValue]; }
- (NSString *)descriptionWithLocale:(NSDictionary *)locale { return NSDecimalString(&_decimal, locale); }

- (instancetype)decimalNumberByRoundingAccordingToBehavior:(id <NSDecimalNumberBehaviors>)behavior { if (behavior == nil) behavior = [[self class] defaultBehavior]; NSDecimal result; NSDecimalRound(&result, &_decimal, [behavior scale], [behavior roundingMode]); return __NSDecimalResult(result); }
- (instancetype)decimalNumberByAdding:(NSDecimalNumber *)number { return [self decimalNumberByAdding:number withBehavior:nil]; }
- (instancetype)decimalNumberByAdding:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { NSDecimal result; NSCalculationError error = NSDecimalAdd(&result, &_decimal, &number->_decimal, behavior == nil ? NSRoundPlain : [behavior roundingMode]); (void)error; return __NSDecimalResult(result); }
- (instancetype)decimalNumberBySubtracting:(NSDecimalNumber *)number { return [self decimalNumberBySubtracting:number withBehavior:nil]; }
- (instancetype)decimalNumberBySubtracting:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { NSDecimal result; NSCalculationError error = NSDecimalSubtract(&result, &_decimal, &number->_decimal, behavior == nil ? NSRoundPlain : [behavior roundingMode]); (void)error; return __NSDecimalResult(result); }
- (instancetype)decimalNumberByMultiplyingBy:(NSDecimalNumber *)number { return [self decimalNumberByMultiplyingBy:number withBehavior:nil]; }
- (instancetype)decimalNumberByMultiplyingBy:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { NSDecimal result; NSCalculationError error = NSDecimalMultiply(&result, &_decimal, &number->_decimal, behavior == nil ? NSRoundPlain : [behavior roundingMode]); (void)error; return __NSDecimalResult(result); }
- (instancetype)decimalNumberByDividingBy:(NSDecimalNumber *)number { return [self decimalNumberByDividingBy:number withBehavior:nil]; }
- (instancetype)decimalNumberByDividingBy:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior { NSDecimal result; NSCalculationError error = NSDecimalDivide(&result, &_decimal, &number->_decimal, behavior == nil ? NSRoundPlain : [behavior roundingMode]); (void)error; return __NSDecimalResult(result); }
- (instancetype)decimalNumberByRaisingToPower:(NSUInteger)power { return [self decimalNumberByRaisingToPower:power withBehavior:nil]; }
- (instancetype)decimalNumberByRaisingToPower:(NSUInteger)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior { NSDecimal result; NSCalculationError error = NSDecimalPower(&result, &_decimal, power, behavior == nil ? NSRoundPlain : [behavior roundingMode]); (void)error; return __NSDecimalResult(result); }
- (instancetype)decimalNumberByMultiplyingByPowerOf10:(short)power { return [self decimalNumberByMultiplyingByPowerOf10:power withBehavior:nil]; }
- (instancetype)decimalNumberByMultiplyingByPowerOf10:(short)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior { NSDecimal result; NSCalculationError error = NSDecimalMultiplyByPowerOf10(&result, &_decimal, power, behavior == nil ? NSRoundPlain : [behavior roundingMode]); (void)error; return __NSDecimalResult(result); }

@end

@implementation NSDecimalNumberHandler
- (instancetype)initWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale { self = [super init]; if (self != nil) { _roundingMode = roundingMode; _scale = scale; } return self; }
- (NSRoundingMode)roundingMode { return _roundingMode; }
- (short)scale { return _scale; }
+ (instancetype)defaultDecimalNumberHandler { return __NSDECIMAL_AUTORELEASE([[self alloc] initWithRoundingMode:NSRoundPlain scale:NSDecimalNoScale]); }
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation error:(NSCalculationError)error leftOperand:(NSDecimalNumber *)leftOperand rightOperand:(NSDecimalNumber *)rightOperand { (void)operation; (void)error; (void)leftOperand; (void)rightOperand; return nil; }
@end
