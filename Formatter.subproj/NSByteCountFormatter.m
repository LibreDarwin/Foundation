/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSByteCountFormatter turns a byte count into a human-readable string.  The
 * unit ladder is decimal (1000-based) for file/decimal counts and binary
 * (1024-based) for memory/binary counts; the numeric part is handed to
 * NSNumberFormatter so grouping and the decimal separator follow the current
 * locale.  The adaptive fraction-digit rule matches Apple's documented
 * behavior: 0 digits for bytes and KB, 1 for MB, 2 for GB and above.
 */

#import <Foundation/NSByteCountFormatter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSMeasurement.h>
#import <Foundation/NSException.h>

/* Index 0 is the byte unit (singular/plural handled separately). */
static const char *kUnitSuffixes[] = { "bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB" };

@implementation NSByteCountFormatter {
    NSByteCountFormatterUnits _allowedUnits;
    NSByteCountFormatterCountStyle _countStyle;
    BOOL _allowsNonnumericFormatting;
    BOOL _includesUnit;
    BOOL _includesCount;
    BOOL _includesActualByteCount;
    BOOL _adaptive;
    BOOL _zeroPadsFractionDigits;
    NSFormattingContext _formattingContext;
}

- (id)init {
    self = [super init];
    if (self) {
        _allowedUnits = NSByteCountFormatterUseDefault;
        _countStyle = NSByteCountFormatterCountStyleFile;
        _allowsNonnumericFormatting = YES;
        _includesUnit = YES;
        _includesCount = YES;
        _includesActualByteCount = NO;
        _adaptive = YES;
        _zeroPadsFractionDigits = NO;
        _formattingContext = NSFormattingContextUnknown;
    }
    return self;
}

+ (NSString *)stringFromByteCount:(long long)byteCount
                       countStyle:(NSByteCountFormatterCountStyle)countStyle {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = countStyle;
    return [formatter stringFromByteCount:byteCount];
}

- (long long)_base {
    switch (_countStyle) {
        case NSByteCountFormatterCountStyleMemory:
        case NSByteCountFormatterCountStyleBinary:
            return 1024;
        case NSByteCountFormatterCountStyleFile:
        case NSByteCountFormatterCountStyleDecimal:
        default:
            return 1000;
    }
}

- (int)_exponentForByteCount:(long long)byteCount base:(long long)base {
    int exponent = 0;
    long long divisor = 1;
    while (exponent < 8 && byteCount / divisor >= base) {
        divisor *= base;
        exponent++;
    }
    return exponent;
}

- (int)_fractionDigitsForExponent:(int)exponent value:(double)value {
    if (_adaptive) {
        if (exponent <= 1) return 0;
        if (exponent == 2) return 1;
        return 2;
    }
    /* Non-adaptive: keep at least three significant digits. */
    if (value >= 100.0) return 0;
    if (value >= 10.0) return 1;
    return 2;
}

- (NSString *)stringFromByteCount:(long long)byteCount {
    /* Apple treats "include neither" as "include both". */
    BOOL includeCount = _includesCount;
    BOOL includeUnit = _includesUnit;
    if (!includeCount && !includeUnit) {
        includeCount = YES;
        includeUnit = YES;
    }

    long long base = [self _base];
    int exponent = 0;
    NSString *countString = nil;
    NSString *unitString = nil;

    if (byteCount == 0 && _allowsNonnumericFormatting) {
        countString = @"Zero";
        unitString = @"KB";
    } else {
        exponent = [self _exponentForByteCount:byteCount base:base];
        double divisor = 1.0;
        for (int i = 0; i < exponent; i++) divisor *= (double)base;
        double value = (double)byteCount / divisor;
        int fractionDigits = [self _fractionDigitsForExponent:exponent value:value];

        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.locale = [NSLocale currentLocale];
        numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        numberFormatter.usesGroupingSeparator = (exponent == 0);
        numberFormatter.minimumFractionDigits = _zeroPadsFractionDigits ? (NSUInteger)fractionDigits : 0;
        numberFormatter.maximumFractionDigits = (NSUInteger)fractionDigits;

        countString = [numberFormatter stringFromNumber:[NSNumber numberWithDouble:value]];
        if (countString == nil) countString = @"";

        if (exponent == 0) {
            unitString = (value == 1.0) ? @"byte" : @"bytes";
        } else {
            unitString = [NSString stringWithUTF8String:kUnitSuffixes[exponent]];
        }
    }

    NSString *result;
    if (includeCount && includeUnit) {
        result = [NSString stringWithFormat:@"%@ %@", countString, unitString];
    } else if (includeCount) {
        result = countString;
    } else {
        result = unitString;
    }

    if (_includesActualByteCount && includeCount && includeUnit && exponent > 0) {
        result = [result stringByAppendingFormat:@" (%lld bytes)", byteCount];
    }

    return result;
}

- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSMeasurement class]]) {
        return [self stringFromMeasurement:(NSMeasurement *)obj];
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [self stringFromByteCount:(long long)[obj longLongValue]];
    }
    return nil;
}

+ (NSString *)stringFromMeasurement:(NSMeasurement *)measurement
                        countStyle:(NSByteCountFormatterCountStyle)countStyle {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = countStyle;
    return [formatter stringFromMeasurement:measurement];
}

- (NSString *)stringFromMeasurement:(NSMeasurement *)measurement {
    NSUnit *unit = [measurement unit];
    if (![unit isKindOfClass:[NSDimension class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSByteCountFormatter stringFromMeasurement:]: "
                           @"unit %@ is not a dimension", unit];
        return nil;
    }
    double bytesDouble = [(NSDimension *)unit converter]
        ? [[(NSDimension *)unit converter] baseUnitValueFromValue:[measurement doubleValue]]
        : [measurement doubleValue];

    /* Restricting to bytes prints the exact byte count, integer-truncated. */
    if (_allowedUnits == NSByteCountFormatterUseBytes) {
        long long bytes = (long long)bytesDouble;
        BOOL includeCount = _includesCount;
        BOOL includeUnit = _includesUnit;
        if (!includeCount && !includeUnit) { includeCount = YES; includeUnit = YES; }

        NSString *countString;
        NSString *unitString;
        if (bytes == 0 && _allowsNonnumericFormatting) {
            countString = @"Zero";
            unitString = @"bytes";
        } else {
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
            numberFormatter.locale = [NSLocale currentLocale];
            numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
            numberFormatter.usesGroupingSeparator = YES;
            numberFormatter.minimumFractionDigits = 0;
            numberFormatter.maximumFractionDigits = 0;
            countString = [numberFormatter stringFromNumber:[NSNumber numberWithLongLong:bytes]];
            if (countString == nil) countString = @"";
            unitString = (bytes == 1) ? @"byte" : @"bytes";
        }

        if (includeCount && includeUnit) {
            return [NSString stringWithFormat:@"%@ %@", countString, unitString];
        }
        if (includeCount) {
            return countString;
        }
        return unitString;
    }

    return [self stringFromByteCount:(long long)bytesDouble];
}

@end
