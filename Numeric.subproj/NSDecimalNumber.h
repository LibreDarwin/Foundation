/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef Foundation_NSDecimalNumber_h
#define Foundation_NSDecimalNumber_h

#import <Foundation/NSNumber.h>
#import <Foundation/NSDecimal.h>

@class NSDictionary;
@class NSString;
@class NSDecimalNumber;

FOUNDATION_EXPORT NSString * const NSDecimalNumberExactnessException;
FOUNDATION_EXPORT NSString * const NSDecimalNumberOverflowException;
FOUNDATION_EXPORT NSString * const NSDecimalNumberUnderflowException;
FOUNDATION_EXPORT NSString * const NSDecimalNumberDivideByZeroException;

@protocol NSDecimalNumberBehaviors
- (NSRoundingMode)roundingMode;
- (short)scale;
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation error:(NSCalculationError)error leftOperand:(NSDecimalNumber *)leftOperand rightOperand:(NSDecimalNumber *)rightOperand;
@end

@interface NSDecimalNumber : NSNumber {
    NSDecimal _decimal;
}

- (instancetype)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative;
- (instancetype)initWithDecimal:(NSDecimal)decimal;
- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithString:(NSString *)string locale:(id)locale;

+ (instancetype)decimalNumberWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)negative;
+ (instancetype)decimalNumberWithDecimal:(NSDecimal)decimal;
+ (instancetype)decimalNumberWithString:(NSString *)string;
+ (instancetype)decimalNumberWithString:(NSString *)string locale:(id)locale;
+ (instancetype)zero;
+ (instancetype)one;
+ (instancetype)minimumDecimalNumber;
+ (instancetype)maximumDecimalNumber;
+ (instancetype)notANumber;

+ (id <NSDecimalNumberBehaviors>)defaultBehavior;
+ (void)setDefaultBehavior:(id <NSDecimalNumberBehaviors>)behavior;

- (NSDecimal)decimalValue;
- (NSComparisonResult)compare:(NSNumber *)number;
- (double)doubleValue;
- (const char *)objCType;
- (NSString *)stringValue;
- (NSString *)descriptionWithLocale:(NSDictionary *)locale;

- (instancetype)decimalNumberByAdding:(NSDecimalNumber *)number;
- (instancetype)decimalNumberByAdding:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior;
- (instancetype)decimalNumberBySubtracting:(NSDecimalNumber *)number;
- (instancetype)decimalNumberBySubtracting:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior;
- (instancetype)decimalNumberByMultiplyingBy:(NSDecimalNumber *)number;
- (instancetype)decimalNumberByMultiplyingBy:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior;
- (instancetype)decimalNumberByDividingBy:(NSDecimalNumber *)number;
- (instancetype)decimalNumberByDividingBy:(NSDecimalNumber *)number withBehavior:(id <NSDecimalNumberBehaviors>)behavior;
- (instancetype)decimalNumberByRaisingToPower:(NSUInteger)power;
- (instancetype)decimalNumberByRaisingToPower:(NSUInteger)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior;
- (instancetype)decimalNumberByMultiplyingByPowerOf10:(short)power;
- (instancetype)decimalNumberByMultiplyingByPowerOf10:(short)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior;
- (instancetype)decimalNumberByRoundingAccordingToBehavior:(id <NSDecimalNumberBehaviors>)behavior;

@end

@interface NSDecimalNumberHandler : NSObject <NSDecimalNumberBehaviors> {
    signed int _scale:16;
    unsigned _roundingMode:3;
    unsigned _raiseOnExactness:1;
    unsigned _raiseOnOverflow:1;
    unsigned _raiseOnUnderflow:1;
    unsigned _raiseOnDivideByZero:1;
    unsigned _unused:9;
    void *_reserved2;
    void *_reserved;
}
- (instancetype)initWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero;
+ (instancetype)decimalNumberHandlerWithRoundingMode:(NSRoundingMode)roundingMode scale:(short)scale raiseOnExactness:(BOOL)exact raiseOnOverflow:(BOOL)overflow raiseOnUnderflow:(BOOL)underflow raiseOnDivideByZero:(BOOL)divideByZero;
+ (instancetype)defaultDecimalNumberHandler;
- (NSRoundingMode)roundingMode;
- (short)scale;
- (BOOL)raiseOnExactness;
- (BOOL)raiseOnOverflow;
- (BOOL)raiseOnUnderflow;
- (BOOL)raiseOnDivideByZero;
@end

#endif
