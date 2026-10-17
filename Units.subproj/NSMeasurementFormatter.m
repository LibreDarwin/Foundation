/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSMeasurementFormatter is a thin wrapper around a private, non-NSObject
 * NSUnitFormatter engine, exactly as on Apple's Foundation.  The engine
 * localizes units through ICU's measure-format API (uameasfmt_*), cloning the
 * number formatter's own UNumberFormat so grouping and digits agree with
 * NSNumberFormatter.  Storage measurements additionally go through a natural
 * -scale pass that mirrors Apple's __NSMeasurementConvertedForFileSize
 * -Description.
 */

#import <Foundation/NSMeasurementFormatter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSCoder.h>
#include <stdint.h>
#include <stdlib.h>

/* ---- ICU C API -----------------------------------------------------------
 * ICU ships no headers alongside libicucore, and this build has no ICU include
 * path, so declare the small surface used here by hand.  The type names are
 * deliberately distinct from ICU's own (LDICUFoo) so these declarations never
 * clash if an ICU header is ever pulled in transitively; only the function
 * symbol names must match libicucore.  ABI-wise every argument is a pointer or
 * a scalar, so the pointee type names are irrelevant.
 */
typedef int32_t LDICUErrorCode;
typedef uint16_t LDICUChar;
typedef struct LDICUNumberFormat_t LDICUNumberFormat;
typedef struct LDICUParseError_t LDICUParseError;
typedef struct LDICUMeasureFormat_t LDICUMeasureFormat;

extern LDICUMeasureFormat *uameasfmt_open(const char *localeID, int32_t width,
                                          LDICUNumberFormat *nf,
                                          LDICUErrorCode *status);
extern int32_t uameasfmt_getUnitName(const LDICUMeasureFormat *mf, uint64_t unit,
                                     LDICUChar *buffer, int32_t capacity,
                                     LDICUErrorCode *status);
extern int32_t uameasfmt_format(const LDICUMeasureFormat *mf, uint64_t unit,
                                LDICUChar *buffer, int32_t capacity,
                                LDICUErrorCode *status, double value);
extern void uameasfmt_close(LDICUMeasureFormat *mf);
extern LDICUNumberFormat *unum_open(int32_t style, const LDICUChar *pattern,
                                    int32_t patternLength, const char *locale,
                                    LDICUParseError *parseErr,
                                    LDICUErrorCode *status);
extern LDICUNumberFormat *unum_clone(const LDICUNumberFormat *fmt,
                                     LDICUErrorCode *status);
extern void unum_close(LDICUNumberFormat *fmt);

/* ICU width constants (UMeasureFormatWidth). */
enum {
    kLDICUMeasureFormatWidthWide   = 0,
    kLDICUMeasureFormatWidthShort  = 1,
    kLDICUMeasureFormatWidthNarrow = 2
};

/* The number-format style passed to unum_open when a fallback is needed. */
enum { kLDICUNumberFormatDecimal = 1 };

/* ---- private collaborators ---------------------------------------------- */

@interface NSNumberFormatter (LDICUFormatAccess)
- (void *)getFormatter;
@end

@interface NSDimension (LDMeasurementScaling)
+ (NSMeasurement *)_measurementWithNaturalScale:(NSMeasurement *)measurement
                                         system:(NSInteger)system;
@end

typedef NS_OPTIONS(NSUInteger, NSUnitFormatterUnitOptions) {
    NSUnitFormatterUnitOptionsProvidedUnit = (1UL << 0),
    NSUnitFormatterUnitOptionsNaturalScale = (1UL << 1),
    NSUnitFormatterUnitOptionsTemperatureWithoutUnit = (1UL << 2)
};

/* The engine.  Deliberately not part of the framework's public surface. */
@interface NSUnitFormatter : NSObject

@property NSUnitFormatterUnitOptions unitOptions;
@property NSFormattingUnitStyle unitStyle;
@property (strong) NSLocale *locale;
@property (strong) NSNumberFormatter *numberFormatter;

- (NSString *)stringForObjectValue:(id)obj;
- (NSString *)stringFromUnit:(NSUnit *)unit;
- (NSString *)stringForValue:(double)value unit:(NSInteger)specifier;

@end

@implementation NSUnitFormatter {
    NSUnitFormatterUnitOptions _unitOptions;
    NSFormattingUnitStyle _unitStyle;
    NSLocale *_locale;
    NSNumberFormatter *_numberFormatter;
    LDICUMeasureFormat *_icuFormatter;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _unitOptions = 0;
        _unitStyle = NSFormattingUnitStyleMedium;
        _locale = [NSLocale currentLocale];
        _numberFormatter = [[NSNumberFormatter alloc] init];
        _numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        _numberFormatter.locale = _locale;
        _icuFormatter = NULL;
    }
    return self;
}

- (void)dealloc {
    if (_icuFormatter != NULL) {
        uameasfmt_close(_icuFormatter);
    }
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (NSUnitFormatterUnitOptions)unitOptions { return _unitOptions; }
- (void)setUnitOptions:(NSUnitFormatterUnitOptions)unitOptions { _unitOptions = unitOptions; }
- (NSFormattingUnitStyle)unitStyle { return _unitStyle; }
- (void)setUnitStyle:(NSFormattingUnitStyle)unitStyle { _unitStyle = unitStyle; }
- (NSLocale *)locale { return _locale; }
/* Setting the locale keeps the number formatter in step, exactly as Apple
 * does: the ICU measure format clones the number formatter's UNumberFormat, so
 * its locale decides grouping and the decimal separator. */
- (void)setLocale:(NSLocale *)locale {
    _locale = locale;
    _numberFormatter.locale = locale;
}
- (NSNumberFormatter *)numberFormatter { return _numberFormatter; }
- (void)setNumberFormatter:(NSNumberFormatter *)numberFormatter { _numberFormatter = numberFormatter; }

/* Build (or rebuild) the ICU measure formatter around a fresh clone of the
 * number formatter's UNumberFormat, so the latest locale/style/number settings
 * are always reflected. */
- (LDICUMeasureFormat *)_measureFormatter {
    if (_icuFormatter != NULL) {
        uameasfmt_close(_icuFormatter);
        _icuFormatter = NULL;
    }

    LDICUErrorCode status = 0;
    void *base = [_numberFormatter getFormatter];
    BOOL ownsBase = NO;
    if (base == NULL) {
        base = unum_open(kLDICUNumberFormatDecimal, NULL, 0, NULL, NULL, &status);
        ownsBase = YES;
    }
    if (base == NULL) {
        return NULL;
    }

    status = 0;
    LDICUNumberFormat *clone = unum_clone((LDICUNumberFormat *)base, &status);
    if (ownsBase) {
        unum_close((LDICUNumberFormat *)base);
    }
    if (clone == NULL) {
        return NULL;
    }

    int32_t width;
    switch (_unitStyle) {
        case NSFormattingUnitStyleShort:
            width = kLDICUMeasureFormatWidthNarrow;
            break;
        case NSFormattingUnitStyleLong:
            width = kLDICUMeasureFormatWidthWide;
            break;
        case NSFormattingUnitStyleMedium:
        default:
            width = kLDICUMeasureFormatWidthShort;
            break;
    }

    const char *localeID = [[_locale localeIdentifier] UTF8String];
    status = 0;
    LDICUMeasureFormat *measureFormatter =
        uameasfmt_open(localeID, width, clone, &status);
    if (measureFormatter == NULL) {
        unum_close(clone);
        return NULL;
    }
    _icuFormatter = measureFormatter;
    return _icuFormatter;
}

static NSString *LDStringFromICUChars(const LDICUChar *chars, int32_t length) {
    if (length <= 0) {
        return nil;
    }
    return [NSString stringWithCharacters:(const unichar *)chars
                                   length:(NSUInteger)length];
}

- (NSString *)_unitNameForSpecifier:(NSInteger)specifier {
    LDICUMeasureFormat *measureFormatter = [self _measureFormatter];
    if (measureFormatter == NULL) {
        return nil;
    }
    LDICUErrorCode status = 0;
    LDICUChar buffer[100];
    int32_t length = uameasfmt_getUnitName(measureFormatter, (uint64_t)specifier,
                                           buffer, 100, &status);
    if (length <= 0) {
        return nil;
    }
    if (length >= 100) {
        LDICUChar *large = malloc(sizeof(LDICUChar) * (size_t)length);
        if (large == NULL) {
            return nil;
        }
        length = uameasfmt_getUnitName(measureFormatter, (uint64_t)specifier,
                                       large, length, &status);
        NSString *name = LDStringFromICUChars(large, length);
        free(large);
        return name;
    }
    return LDStringFromICUChars(buffer, length);
}

- (NSString *)stringForValue:(double)value unit:(NSInteger)specifier {
    LDICUMeasureFormat *measureFormatter = [self _measureFormatter];
    if (measureFormatter == NULL) {
        return nil;
    }
    LDICUErrorCode status = 0;
    LDICUChar buffer[100];
    int32_t length = uameasfmt_format(measureFormatter, (uint64_t)specifier,
                                      buffer, 100, &status, value);
    if (length <= 0) {
        return nil;
    }
    if (length >= 100) {
        LDICUChar *large = malloc(sizeof(LDICUChar) * (size_t)length);
        if (large == NULL) {
            return nil;
        }
        length = uameasfmt_format(measureFormatter, (uint64_t)specifier, large,
                                  length, &status, value);
        NSString *formatted = LDStringFromICUChars(large, length);
        free(large);
        return formatted;
    }
    return LDStringFromICUChars(buffer, length);
}

- (BOOL)_unitHasSpecifier:(NSUnit *)unit {
    if (![unit isKindOfClass:[NSDimension class]]) {
        return NO;
    }
    if (![unit respondsToSelector:@selector(specifier)]) {
        return NO;
    }
    return [(NSDimension *)unit specifier] != -1;
}

/* Maps an ICU storage specifier back to the framework's canonical unit.  Only
 * information-storage units are reproduced here; other dimensions fall back to
 * the measurement's own unit (no conversion). */
- (NSUnit *)_dimensionUnitForSpecifier:(NSInteger)specifier {
    switch (specifier) {
        case 0xE00: return [NSUnitInformationStorage bits];
        case 0xE01: return [NSUnitInformationStorage bytes];
        case 0xE02: return [NSUnitInformationStorage gigabits];
        case 0xE03: return [NSUnitInformationStorage gigabytes];
        case 0xE04: return [NSUnitInformationStorage kilobits];
        case 0xE05: return [NSUnitInformationStorage kilobytes];
        case 0xE06: return [NSUnitInformationStorage megabits];
        case 0xE07: return [NSUnitInformationStorage megabytes];
        case 0xE08: return [NSUnitInformationStorage terabits];
        case 0xE09: return [NSUnitInformationStorage terabytes];
        case 0xE0A: return [NSUnitInformationStorage petabytes];
        default:    return nil;
    }
}

- (NSString *)stringFromUnit:(NSUnit *)unit {
    if ([self _unitHasSpecifier:unit]) {
        return [self _unitNameForSpecifier:[(NSDimension *)unit specifier]];
    }
    return [unit symbol];
}

- (NSString *)_symbolStringForMeasurement:(NSMeasurement *)measurement {
    NSString *number =
        [_numberFormatter stringFromNumber:@([measurement doubleValue])];
    return [NSString stringWithFormat:@"%@ %@", number,
                                      [[measurement unit] symbol]];
}

/* Terminal step: an ICU-capable unit is formatted by ICU; anything else (a
 * binary unit chosen by natural scaling, or a specifier-less unit) falls back
 * to "<number> <symbol>". */
- (NSString *)_stringForScaledMeasurement:(NSMeasurement *)measurement {
    NSUnit *unit = [measurement unit];
    if ([self _unitHasSpecifier:unit]) {
        return [self stringForValue:[measurement doubleValue]
                               unit:[(NSDimension *)unit specifier]];
    }
    return [self _symbolStringForMeasurement:measurement];
}

- (NSString *)stringForObjectValue:(id)obj {
    if (![obj isKindOfClass:[NSMeasurement class]]) {
        return nil;
    }
    NSMeasurement *measurement = obj;
    NSUnit *unit = [measurement unit];

    if ([self _unitHasSpecifier:unit]) {
        NSInteger specifier = [(NSDimension *)unit specifier];
        NSMeasurement *scaled = measurement;
        NSUnit *dimensionUnit = [self _dimensionUnitForSpecifier:specifier];
        if (dimensionUnit != nil) {
            scaled = [scaled measurementByConvertingToUnit:dimensionUnit];
        }
        if (_unitOptions & NSUnitFormatterUnitOptionsNaturalScale) {
            if ([[scaled unit] isKindOfClass:[NSDimension class]]) {
                scaled = [[[scaled unit] class] _measurementWithNaturalScale:scaled
                                                                      system:0];
            }
        }
        return [self _stringForScaledMeasurement:scaled];
    }

    BOOL dimensional = [unit isKindOfClass:[NSDimension class]];
    if ((_unitOptions & NSUnitFormatterUnitOptionsProvidedUnit) || !dimensional) {
        return [self _symbolStringForMeasurement:measurement];
    }

    NSUnit *baseUnit = [[unit class] baseUnit];
    if (![self _unitHasSpecifier:baseUnit]) {
        return nil;
    }
    NSMeasurement *converted = [measurement measurementByConvertingToUnit:baseUnit];
    return [self stringForObjectValue:converted];
}

@end

@implementation NSMeasurementFormatter {
    NSUnitFormatter *_unitFormatter;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _unitFormatter = [[NSUnitFormatter alloc] init];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _unitFormatter = [[NSUnitFormatter alloc] init];
        _unitFormatter.unitOptions =
            (NSUnitFormatterUnitOptions)[coder decodeIntegerForKey:@"NSUnitOptions"];
        _unitFormatter.unitStyle =
            (NSFormattingUnitStyle)[coder decodeIntegerForKey:@"NSUnitStyle"];
        NSLocale *locale = [coder decodeObjectOfClass:[NSLocale class]
                                               forKey:@"NSLocale"];
        if (locale != nil) {
            _unitFormatter.locale = locale;
        }
        NSNumberFormatter *numberFormatter =
            [coder decodeObjectOfClass:[NSNumberFormatter class]
                                forKey:@"NSNumberFormatter"];
        if (numberFormatter != nil) {
            _unitFormatter.numberFormatter = numberFormatter;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:_unitFormatter.unitOptions forKey:@"NSUnitOptions"];
    [coder encodeInteger:_unitFormatter.unitStyle forKey:@"NSUnitStyle"];
    [coder encodeObject:_unitFormatter.locale forKey:@"NSLocale"];
    [coder encodeObject:_unitFormatter.numberFormatter forKey:@"NSNumberFormatter"];
}

- (NSMeasurementFormatterUnitOptions)unitOptions {
    return (NSMeasurementFormatterUnitOptions)_unitFormatter.unitOptions;
}

- (void)setUnitOptions:(NSMeasurementFormatterUnitOptions)unitOptions {
    _unitFormatter.unitOptions = (NSUnitFormatterUnitOptions)unitOptions;
}

- (NSFormattingUnitStyle)unitStyle {
    return _unitFormatter.unitStyle;
}

- (void)setUnitStyle:(NSFormattingUnitStyle)unitStyle {
    _unitFormatter.unitStyle = unitStyle;
}

- (NSLocale *)locale {
    return _unitFormatter.locale;
}

- (void)setLocale:(NSLocale *)locale {
    _unitFormatter.locale = locale ? locale : [NSLocale currentLocale];
}

- (NSNumberFormatter *)numberFormatter {
    return _unitFormatter.numberFormatter;
}

- (void)setNumberFormatter:(NSNumberFormatter *)numberFormatter {
    if (numberFormatter == nil) {
        numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        numberFormatter.locale = _unitFormatter.locale;
    }
    _unitFormatter.numberFormatter = numberFormatter;
}

- (NSString *)stringFromMeasurement:(NSMeasurement *)measurement {
    return [_unitFormatter stringForObjectValue:measurement];
}

- (NSString *)stringFromUnit:(NSUnit *)unit {
    return [_unitFormatter stringFromUnit:unit];
}

- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSMeasurement class]]) {
        return [self stringFromMeasurement:obj];
    }
    return nil;
}

@end
