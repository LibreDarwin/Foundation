/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef Foundation_NSDecimal_h
#define Foundation_NSDecimal_h

#include <limits.h>
#include <Foundation/NSObjCRuntime.h>

@class NSString;
@class NSDictionary;

typedef NS_ENUM(NSUInteger, NSRoundingMode) {
    NSRoundPlain,
    NSRoundDown,
    NSRoundUp,
    NSRoundBankers
};

typedef NS_ENUM(NSUInteger, NSCalculationError) {
    NSCalculationNoError = 0,
    NSCalculationLossOfPrecision,
    NSCalculationUnderflow,
    NSCalculationOverflow,
    NSCalculationDivideByZero
};

#define NSDecimalMaxSize 8
#define NSDecimalNoScale SHRT_MAX

typedef struct NSDecimal {
    signed int _exponent:8;
    unsigned int _length:4;
    unsigned int _isNegative:1;
    unsigned int _isCompact:1;
    unsigned int _reserved:18;
    unsigned short _mantissa[NSDecimalMaxSize];
} NSDecimal;

NS_INLINE BOOL NSDecimalIsNotANumber(const NSDecimal *decimal) {
    return decimal->_length == 0 && decimal->_isNegative;
}

FOUNDATION_EXPORT void NSDecimalCopy(NSDecimal *destination, const NSDecimal *source);
FOUNDATION_EXPORT void NSDecimalCompact(NSDecimal *number);
FOUNDATION_EXPORT NSComparisonResult NSDecimalCompare(const NSDecimal *left, const NSDecimal *right);
FOUNDATION_EXPORT void NSDecimalRound(NSDecimal *result, const NSDecimal *number, NSInteger scale, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalAdd(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalSubtract(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalMultiply(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalDivide(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalPower(NSDecimal *result, const NSDecimal *number, NSUInteger power, NSRoundingMode mode);
FOUNDATION_EXPORT NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number, short power, NSRoundingMode mode);
FOUNDATION_EXPORT NSString *NSDecimalString(const NSDecimal *decimal, NSDictionary *locale);

#endif
