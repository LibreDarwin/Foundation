/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import "NSDecimal.h"
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#include <string.h>
#include <stdlib.h>

#define DECIMAL_DIGITS 256
#define DECIMAL_RESULT_DIGITS 39

typedef struct {
    unsigned char digits[DECIMAL_DIGITS];
    unsigned int count;
    int exponent;
    BOOL negative;
    BOOL nan;
} DecimalDigits;

static void decimal_clear(DecimalDigits *decimal) { memset(decimal, 0, sizeof(*decimal)); }

static void decimal_trim(DecimalDigits *decimal) {
    unsigned int offset = 0;
    while (offset < decimal->count && decimal->digits[offset] == 0) offset++;
    if (offset != 0) {
        decimal->count -= offset;
        memmove(decimal->digits, decimal->digits + offset, decimal->count);
    }
    while (decimal->count != 0 && decimal->digits[decimal->count - 1] == 0) {
        decimal->count--;
        decimal->exponent++;
    }
    if (decimal->count == 0) {
        decimal->exponent = 0;
        decimal->negative = NO;
    }
}

static void decimal_from_ns_raw(DecimalDigits *out, const NSDecimal *source) {
    decimal_clear(out);
    out->exponent = source->_exponent;
    out->negative = source->_isNegative;
    out->nan = NSDecimalIsNotANumber(source);
    if (out->nan || source->_length == 0) return;

    for (int word = source->_length - 1; word >= 0; word--) {
        unsigned int carry = source->_mantissa[word];
        for (int index = (int)out->count - 1; index >= 0; index--) {
            unsigned int value = out->digits[index] * 65536U + carry;
            out->digits[index] = (unsigned char)(value % 10U);
            carry = value / 10U;
        }
        while (carry != 0) {
            memmove(out->digits + 1, out->digits, out->count);
            out->digits[0] = (unsigned char)(carry % 10U);
            carry /= 10U;
            out->count++;
        }
    }
}

static void decimal_from_ns(DecimalDigits *out, const NSDecimal *source) {
    decimal_from_ns_raw(out, source);
    decimal_trim(out);
}

static void decimal_from_ascii(DecimalDigits *out, const char *text) {
    decimal_clear(out);
    const char *cursor = text;
    if (*cursor == '-') { out->negative = YES; cursor++; }
    else if (*cursor == '+') cursor++;
    int fractional = 0;
    BOOL afterDecimal = NO;
    while (*cursor != 0 && *cursor != 'e' && *cursor != 'E') {
        if (*cursor == '.') { afterDecimal = YES; cursor++; continue; }
        if (*cursor >= '0' && *cursor <= '9') {
            if (out->count < DECIMAL_DIGITS) out->digits[out->count++] = (unsigned char)(*cursor - '0');
            if (afterDecimal) fractional++;
        }
        cursor++;
    }
    int scientificExponent = 0;
    if (*cursor == 'e' || *cursor == 'E') scientificExponent = (int)strtol(cursor + 1, NULL, 10);
    out->exponent = scientificExponent - fractional;
    decimal_trim(out);
}

static BOOL decimal_digits_exceed_max(const DecimalDigits *digits) {
    if (digits->count != DECIMAL_RESULT_DIGITS) return NO;
    static const char maxMantissa[] = "340282366920938463463374607431768211455";
    for (unsigned int i = 0; i < digits->count; i++) {
        unsigned char digit = (unsigned char)(maxMantissa[i] - '0');
        if (digits->digits[i] != digit) return digits->digits[i] > digit;
    }
    return NO;
}

static NSCalculationError decimal_to_ns(NSDecimal *out, DecimalDigits *source, NSRoundingMode mode) {
    decimal_trim(source);
    memset(out, 0, sizeof(*out));
    out->_exponent = source->exponent;
    out->_isNegative = source->negative;
    out->_isCompact = 1;
    if (source->nan) {
        out->_isNegative = 1;
        return NSCalculationNoError;
    }
    BOOL lost = NO;
    while (source->count > DECIMAL_RESULT_DIGITS) {
        unsigned int kept = DECIMAL_RESULT_DIGITS;
        unsigned char guard = source->digits[kept];
        BOOL nonzeroTail = guard != 0;
        for (unsigned int index = kept + 1; index < source->count; index++) {
            if (source->digits[index] != 0) { nonzeroTail = YES; break; }
        }
        lost = lost || nonzeroTail;
        unsigned int droppedCount = source->count - kept;
        source->count = kept;
        source->exponent += (int)droppedCount;
        BOOL roundUp = NO;
        if (mode == NSRoundUp) roundUp = !source->negative && nonzeroTail;
        else if (mode == NSRoundDown) roundUp = source->negative && nonzeroTail;
        else if (mode == NSRoundBankers) roundUp = guard > 5 || (guard == 5 && (nonzeroTail || (source->count != 0 && (source->digits[source->count - 1] & 1))));
        else roundUp = guard >= 5;
        if (roundUp) {
            int index = (int)source->count - 1;
            while (index >= 0 && source->digits[index] == 9) source->digits[index--] = 0;
            if (index < 0) {
                memmove(source->digits + 1, source->digits, source->count);
                source->digits[0] = 1;
                source->count++;
            } else source->digits[index]++;
        }
    }
    if (decimal_digits_exceed_max(source)) {
        if (source->count != 0 && source->digits[source->count - 1] != 0) lost = YES;
        source->count--;
        source->exponent++;
    }
    decimal_trim(source);
    if (source->count != 0 && source->exponent > SCHAR_MAX) {
        memset(out, 0, sizeof(*out));
        out->_isNegative = 1;
        return NSCalculationOverflow;
    }
    if (source->count != 0 && source->exponent < SCHAR_MIN) {
        memset(out, 0, sizeof(*out));
        return NSCalculationUnderflow;
    }
    out->_exponent = source->exponent;
    unsigned short words[NSDecimalMaxSize] = {0};
    unsigned int wordCount = 0;
    for (unsigned int i = 0; i < source->count; i++) {
        unsigned int carry = source->digits[i];
        for (unsigned int j = 0; j < wordCount; j++) {
            unsigned int value = words[j] * 10U + carry;
            words[j] = (unsigned short)(value & 0xffffU);
            carry = value >> 16;
        }
        if (carry != 0 && wordCount < NSDecimalMaxSize) words[wordCount++] = (unsigned short)carry;
    }
    out->_length = wordCount;
    for (unsigned int i = 0; i < wordCount; i++) out->_mantissa[i] = words[i];
    if (wordCount == 0) out->_isNegative = 0;
    return lost ? NSCalculationLossOfPrecision : NSCalculationNoError;
}

static int decimal_magnitude_compare(const DecimalDigits *left, const DecimalDigits *right) {
    int leftMagnitude = (int)left->count + left->exponent;
    int rightMagnitude = (int)right->count + right->exponent;
    if (leftMagnitude != rightMagnitude) return leftMagnitude < rightMagnitude ? -1 : 1;
    unsigned int count = left->count < right->count ? left->count : right->count;
    for (unsigned int i = 0; i < count; i++) if (left->digits[i] != right->digits[i]) return left->digits[i] < right->digits[i] ? -1 : 1;
    for (unsigned int i = count; i < left->count; i++) if (left->digits[i] != 0) return 1;
    for (unsigned int i = count; i < right->count; i++) if (right->digits[i] != 0) return -1;
    return 0;
}

static BOOL decimal_scale_to(DecimalDigits *decimal, int exponent) {
    if (decimal->count == 0 || decimal->exponent == exponent) return YES;
    int zeros = decimal->exponent - exponent;
    if (zeros < 0 || decimal->count + (unsigned int)zeros > DECIMAL_DIGITS) return NO;
    memset(decimal->digits + decimal->count, 0, (size_t)zeros);
    decimal->count += (unsigned int)zeros;
    decimal->exponent = exponent;
    return YES;
}

static NSCalculationError decimal_add_digits(DecimalDigits *out, DecimalDigits left, DecimalDigits right, NSRoundingMode mode) {
    int exponent = left.exponent < right.exponent ? left.exponent : right.exponent;
    decimal_scale_to(&left, exponent);
    decimal_scale_to(&right, exponent);
    unsigned int count = left.count > right.count ? left.count : right.count;
    memset(out, 0, sizeof(*out));
    out->count = count;
    out->exponent = exponent;
    int carry = 0;
    for (int i = (int)count - 1; i >= 0; i--) {
        int li = i - ((int)count - (int)left.count);
        int ri = i - ((int)count - (int)right.count);
        int value = (li >= 0 ? left.digits[li] : 0) + (ri >= 0 ? right.digits[ri] : 0) + carry;
        out->digits[i] = (unsigned char)(value % 10);
        carry = value / 10;
    }
    if (carry) { memmove(out->digits + 1, out->digits, out->count); out->digits[0] = (unsigned char)carry; out->count++; }
    decimal_trim(out);
    (void)mode;
    return out->count > DECIMAL_RESULT_DIGITS ? NSCalculationLossOfPrecision : NSCalculationNoError;
}

static void decimal_subtract_digits(DecimalDigits *out, DecimalDigits left, DecimalDigits right) {
    int exponent = left.exponent < right.exponent ? left.exponent : right.exponent;
    decimal_scale_to(&left, exponent);
    decimal_scale_to(&right, exponent);
    out->count = left.count;
    out->exponent = exponent;
    out->negative = left.negative;
    int borrow = 0;
    for (int i = (int)left.count - 1; i >= 0; i--) {
        int ri = i - ((int)left.count - (int)right.count);
        int value = left.digits[i] - (ri >= 0 ? right.digits[ri] : 0) - borrow;
        if (value < 0) { value += 10; borrow = 1; } else borrow = 0;
        out->digits[i] = (unsigned char)value;
    }
    decimal_trim(out);
}

static int decimal_integer_compare(const DecimalDigits *left, const DecimalDigits *right) {
    if (left->count != right->count) return left->count < right->count ? -1 : 1;
    for (unsigned int i = 0; i < left->count; i++) {
        if (left->digits[i] != right->digits[i]) return left->digits[i] < right->digits[i] ? -1 : 1;
    }
    return 0;
}

static void decimal_pack_ns(NSDecimal *out, const DecimalDigits *source) {
    memset(out, 0, sizeof(*out));
    out->_exponent = source->exponent;
    out->_isNegative = source->negative;
    unsigned short words[NSDecimalMaxSize] = {0};
    unsigned int wordCount = 0;
    for (unsigned int i = 0; i < source->count; i++) {
        unsigned int carry = source->digits[i];
        for (unsigned int j = 0; j < wordCount; j++) {
            unsigned int value = words[j] * 10U + carry;
            words[j] = (unsigned short)(value & 0xffffU);
            carry = value >> 16;
        }
        if (carry != 0 && wordCount < NSDecimalMaxSize) words[wordCount++] = (unsigned short)carry;
    }
    out->_length = wordCount;
    for (unsigned int i = 0; i < wordCount; i++) out->_mantissa[i] = words[i];
    if (wordCount == 0) out->_isNegative = 0;
    out->_isCompact = source->count != 0 && source->digits[source->count - 1] != 0;
}

void NSDecimalCopy(NSDecimal *destination, const NSDecimal *source) { if (destination != source) memcpy(destination, source, sizeof(*destination)); }
void NSDecimalCompact(NSDecimal *number) { DecimalDigits decimal; decimal_from_ns(&decimal, number); (void)decimal_to_ns(number, &decimal, NSRoundPlain); }

NSComparisonResult NSDecimalCompare(const NSDecimal *left, const NSDecimal *right) {
    DecimalDigits a, b; decimal_from_ns(&a, left); decimal_from_ns(&b, right);
    if (a.nan || b.nan) return a.nan == b.nan ? NSOrderedSame : (a.nan ? NSOrderedAscending : NSOrderedDescending);
    if (a.count == 0 && b.count == 0) return NSOrderedSame;
    if (a.negative != b.negative) return a.negative ? NSOrderedAscending : NSOrderedDescending;
    int comparison = decimal_magnitude_compare(&a, &b);
    return a.negative ? (NSComparisonResult)-comparison : (NSComparisonResult)comparison;
}

void NSDecimalRound(NSDecimal *result, const NSDecimal *number, NSInteger scale, NSRoundingMode mode) {
    DecimalDigits decimal; decimal_from_ns(&decimal, number);
    if (!decimal.nan && decimal.count != 0 && scale != NSDecimalNoScale) {
        int keep = (int)decimal.count + decimal.exponent + (int)scale;
        if (keep <= 0) { decimal.count = 0; decimal.exponent = 0; decimal.negative = NO; }
        else if ((unsigned int)keep < decimal.count) {
            unsigned char guard = decimal.digits[keep];
            BOOL tail = NO;
            for (unsigned int i = (unsigned int)keep + 1; i < decimal.count; i++) {
                if (decimal.digits[i] != 0) { tail = YES; break; }
            }
            BOOL roundUp = NO;
            if (mode == NSRoundUp) roundUp = (guard != 0 || tail) && !decimal.negative;
            else if (mode == NSRoundDown) roundUp = (guard != 0 || tail) && decimal.negative;
            else if (mode == NSRoundBankers) roundUp = guard > 5 || (guard == 5 && (tail || (decimal.digits[keep - 1] & 1)));
            else roundUp = guard >= 5;
            decimal.count = (unsigned int)keep;
            decimal.exponent = -(int)scale;
            if (roundUp) { int i = (int)decimal.count - 1; while (i >= 0 && decimal.digits[i] == 9) decimal.digits[i--] = 0; if (i < 0) { memmove(decimal.digits + 1, decimal.digits, decimal.count); decimal.digits[0] = 1; decimal.count++; } else decimal.digits[i]++; }
        }
    }
    (void)decimal_to_ns(result, &decimal, mode);
}

NSCalculationError NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2, NSRoundingMode mode) {
    DecimalDigits a, b; decimal_from_ns(&a, number1); decimal_from_ns(&b, number2);
    if (a.nan || b.nan || a.count == 0 || b.count == 0 || a.exponent == b.exponent) return NSCalculationNoError;
    int exponent = a.exponent < b.exponent ? a.exponent : b.exponent;
    BOOL exact = decimal_scale_to(&a, exponent) && decimal_scale_to(&b, exponent);
    decimal_pack_ns(number1, &a);
    decimal_pack_ns(number2, &b);
    return exact ? NSCalculationNoError : NSCalculationLossOfPrecision;
}

NSCalculationError NSDecimalAdd(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode) {
    DecimalDigits a, b, out; decimal_from_ns(&a, left); decimal_from_ns(&b, right); if (a.nan || b.nan) { memset(result, 0, sizeof(*result)); result->_isNegative = 1; return NSCalculationOverflow; }
    NSCalculationError error = NSCalculationNoError;
    if (a.negative == b.negative) { error = decimal_add_digits(&out, a, b, mode); out.negative = a.negative; }
    else { int comparison = decimal_magnitude_compare(&a, &b); if (comparison == 0) { decimal_clear(&out); } else if (comparison > 0) decimal_subtract_digits(&out, a, b); else { decimal_subtract_digits(&out, b, a); out.negative = b.negative; } }
    NSCalculationError fit = decimal_to_ns(result, &out, mode);
    return error != NSCalculationNoError ? error : fit;
}

NSCalculationError NSDecimalSubtract(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode) {
    NSDecimal inverted = *right; inverted._isNegative = !inverted._isNegative; return NSDecimalAdd(result, left, &inverted, mode);
}

NSCalculationError NSDecimalMultiply(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode) {
    DecimalDigits a, b, out; decimal_from_ns(&a, left); decimal_from_ns(&b, right); decimal_clear(&out); if (a.nan || b.nan) { memset(result, 0, sizeof(*result)); result->_isNegative = 1; return NSCalculationOverflow; }
    if (a.count == 0 || b.count == 0) { (void)decimal_to_ns(result, &out, mode); return NSCalculationNoError; }
    unsigned int temp[DECIMAL_DIGITS * 2] = {0};
    for (int i = (int)a.count - 1; i >= 0; i--) for (int j = (int)b.count - 1; j >= 0; j--) temp[i + j + 1] += a.digits[i] * b.digits[j];
    unsigned int productCount = a.count + b.count;
    for (int i = (int)productCount - 1; i > 0; i--) { temp[i - 1] += temp[i] / 10; temp[i] %= 10; }
    unsigned int first = 0; while (first < productCount && temp[first] == 0) first++;
    out.count = productCount - first; if (out.count > DECIMAL_DIGITS) out.count = DECIMAL_DIGITS;
    for (unsigned int i = 0; i < out.count; i++) out.digits[i] = (unsigned char)temp[first + i];
    out.exponent = a.exponent + b.exponent; out.negative = a.negative != b.negative; decimal_trim(&out); NSCalculationError error = decimal_to_ns(result, &out, mode); return error;
}

NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number, short power, NSRoundingMode mode) { DecimalDigits decimal; decimal_from_ns(&decimal, number); int exponent = decimal.exponent + power; if (exponent > SCHAR_MAX) { decimal.nan = YES; (void)decimal_to_ns(result, &decimal, mode); return NSCalculationOverflow; } if (exponent < SCHAR_MIN) { decimal.nan = YES; (void)decimal_to_ns(result, &decimal, mode); return NSCalculationUnderflow; } decimal.exponent = exponent; return decimal_to_ns(result, &decimal, mode); }

NSCalculationError NSDecimalPower(NSDecimal *result, const NSDecimal *number, NSUInteger power, NSRoundingMode mode) {
    NSDecimal base = *number, value = {0}; value._mantissa[0] = 1; value._length = 1; value._isCompact = 1;
    NSCalculationError error = NSCalculationNoError;
    while (power != 0) {
        if (power & 1) {
            NSCalculationError step = NSDecimalMultiply(&value, &value, &base, mode);
            if (error == NSCalculationNoError) error = step;
        }
        power >>= 1;
        if (power != 0) {
            NSCalculationError step = NSDecimalMultiply(&base, &base, &base, mode);
            if (error == NSCalculationNoError) error = step;
        }
    }
    *result = value;
    return error;
}

static void decimal_integer_append(DecimalDigits *decimal, unsigned char digit) {
    if (decimal->count == 0 && digit == 0) return;
    if (decimal->count < DECIMAL_DIGITS) decimal->digits[decimal->count++] = digit;
}

static void decimal_integer_trim(DecimalDigits *decimal) {
    unsigned int offset = 0;
    while (offset < decimal->count && decimal->digits[offset] == 0) offset++;
    if (offset != 0) {
        decimal->count -= offset;
        memmove(decimal->digits, decimal->digits + offset, decimal->count);
    }
}

static void decimal_integer_subtract(DecimalDigits *left, const DecimalDigits *right) {
    int borrow = 0;
    for (int i = (int)left->count - 1; i >= 0; i--) {
        int rightIndex = i - ((int)left->count - (int)right->count);
        int value = left->digits[i] - (rightIndex >= 0 ? right->digits[rightIndex] : 0) - borrow;
        if (value < 0) { value += 10; borrow = 1; } else borrow = 0;
        left->digits[i] = (unsigned char)value;
    }
    decimal_integer_trim(left);
}

NSCalculationError NSDecimalDivide(NSDecimal *result, const NSDecimal *left, const NSDecimal *right, NSRoundingMode mode) {
    (void)mode;
    DecimalDigits a, b, remainder, quotient;
    decimal_from_ns(&a, left);
    decimal_from_ns(&b, right);
    decimal_clear(&remainder);
    decimal_clear(&quotient);
    if (a.nan || b.nan) { memset(result, 0, sizeof(*result)); result->_isNegative = 1; return NSCalculationOverflow; }
    if (b.count == 0) { memset(result, 0, sizeof(*result)); result->_isNegative = 1; return NSCalculationDivideByZero; }
    if (a.count == 0) { memset(result, 0, sizeof(*result)); return NSCalculationNoError; }

    for (unsigned int i = 0; i < a.count; i++) {
        decimal_integer_append(&remainder, a.digits[i]);
        unsigned char digit = 0;
        while (remainder.count != 0 && decimal_integer_compare(&remainder, &b) >= 0) {
            decimal_integer_subtract(&remainder, &b);
            digit++;
        }
        if (quotient.count != 0 || digit != 0 || i == a.count - 1) quotient.digits[quotient.count++] = digit;
    }
    unsigned int intDigits = quotient.count;

    while (quotient.count < intDigits + 38 && quotient.count < DECIMAL_DIGITS) {
        decimal_integer_append(&remainder, 0);
        unsigned char digit = 0;
        while (remainder.count != 0 && decimal_integer_compare(&remainder, &b) >= 0) {
            decimal_integer_subtract(&remainder, &b);
            digit++;
        }
        quotient.digits[quotient.count++] = digit;
    }

    unsigned int first = 0;
    while (first < quotient.count && quotient.digits[first] == 0) first++;
    if (first == quotient.count) { memset(result, 0, sizeof(*result)); return NSCalculationNoError; }
    memmove(quotient.digits, quotient.digits + first, quotient.count - first);
    quotient.count -= first;

    unsigned short words[NSDecimalMaxSize] = {0};
    unsigned int kept = 0;
    for (unsigned int i = 0; i < quotient.count; i++) {
        unsigned int carry = quotient.digits[i];
        for (unsigned int j = 0; j < NSDecimalMaxSize; j++) {
            unsigned int value = words[j] * 10U + carry;
            words[j] = (unsigned short)(value & 0xffffU);
            carry = value >> 16;
        }
        if (carry != 0) break;
        kept++;
    }
    unsigned int dropped = quotient.count - kept;

    int exponent = a.exponent - b.exponent - 38 + (int)dropped;
    if (exponent > SCHAR_MAX) { memset(result, 0, sizeof(*result)); result->_isNegative = 1; return NSCalculationOverflow; }
    if (exponent < SCHAR_MIN) { memset(result, 0, sizeof(*result)); result->_isNegative = 1; return NSCalculationUnderflow; }

    while (kept > 1 && quotient.digits[kept - 1] == 0 && exponent < SCHAR_MAX) {
        kept--;
        exponent++;
    }

    memset(words, 0, sizeof(words));
    unsigned int wordCount = 0;
    for (unsigned int i = 0; i < kept; i++) {
        unsigned int carry = quotient.digits[i];
        for (unsigned int j = 0; j < wordCount; j++) {
            unsigned int value = words[j] * 10U + carry;
            words[j] = (unsigned short)(value & 0xffffU);
            carry = value >> 16;
        }
        if (carry != 0 && wordCount < NSDecimalMaxSize) words[wordCount++] = (unsigned short)carry;
    }
    memset(result, 0, sizeof(*result));
    result->_exponent = (signed char)exponent;
    result->_isNegative = a.negative != b.negative;
    result->_isCompact = 1;
    wordCount = 0;
    for (unsigned int i = 0; i < NSDecimalMaxSize; i++) if (words[i] != 0) wordCount = i + 1;
    result->_length = wordCount;
    for (unsigned int i = 0; i < wordCount; i++) result->_mantissa[i] = words[i];
    if (wordCount == 0) result->_isNegative = 0;
    return NSCalculationNoError;
}

NSString *NSDecimalString(const NSDecimal *decimal, NSDictionary *locale) {
    DecimalDigits value;
    decimal_from_ns_raw(&value, decimal);
    if (value.nan) return [NSString stringWithUTF8String:"NaN"];
    char buffer[DECIMAL_DIGITS + 64];
    unsigned int position = 0;
    if (value.negative) buffer[position++] = '-';
    if (value.count == 0) {
        buffer[position++] = '0';
    } else if (value.exponent >= 0) {
        for (unsigned int i = 0; i < value.count; i++) buffer[position++] = (char)('0' + value.digits[i]);
        while (value.exponent-- > 0) buffer[position++] = '0';
    } else {
        int point = (int)value.count + value.exponent;
        if (point > 0) {
            for (int i = 0; i < point; i++) buffer[position++] = (char)('0' + value.digits[i]);
            buffer[position++] = '.';
            for (unsigned int i = (unsigned int)point; i < value.count; i++) buffer[position++] = (char)('0' + value.digits[i]);
        } else {
            buffer[position++] = '0';
            buffer[position++] = '.';
            while (point++ < 0) buffer[position++] = '0';
            for (unsigned int i = 0; i < value.count; i++) buffer[position++] = (char)('0' + value.digits[i]);
        }
    }
    buffer[position] = 0;
    NSString *string = [NSString stringWithUTF8String:buffer];
    NSString *separator = [locale objectForKey:@"NSDecimalSeparator"];
    if (separator != nil && [separator length] != 0 && ![separator isEqualToString:@"."]) {
        string = [string stringByReplacingOccurrencesOfString:@"." withString:separator];
    }
    return string;
}
