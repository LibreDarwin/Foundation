/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSNumberFormatter is an owning wrapper around CFNumberFormatter (like
 * NSDateFormatter wraps CFDateFormatter): it creates a CFLocale-backed
 * CFNumberFormatter and answers every value through it.
 */

#import <Foundation/NSNumberFormatter.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFLocale.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFNumberFormatter.h>
#include <CoreFoundation/CFString.h>

#if __has_feature(objc_arc)
#define NNFORMATTER_TRANSFER(value) ((__bridge_transfer id)(value))
#define NNFORMATTER_CF(type, value) ((__bridge type)(value))
#else
#define NNFORMATTER_TRANSFER(value) ((id)CFAutorelease(value))
#define NNFORMATTER_CF(type, value) ((type)(value))
#endif

/* NSLocale owns its CFLocale rather than being toll-free with it; extract the
 * backing locale for CFNumberFormatterCreate and, on the getter, rewrap the
 * formatter's locale through the private initializer. */
@interface NSLocale ()
- (CFLocaleRef)_backingLocale;
- (instancetype)_initWithBackingLocale:(CFLocaleRef)backing;
@end

@implementation NSNumberFormatter {
    CFNumberFormatterRef _formatter;
    NSString *_customFormat;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _formatter = CFNumberFormatterCreate(
            kCFAllocatorDefault, CFLocaleCopyCurrent(), kCFNumberFormatterNoStyle);
        if (_formatter == NULL) return nil;
        _customFormat = nil;
    }
    return self;
}

- (void)dealloc {
    if (_formatter != NULL) CFRelease(_formatter);
#if !__has_feature(objc_arc)
    [_customFormat release];
    [super dealloc];
#endif
}

/* Recreate the backing formatter, keeping any explicitly-set format so a
 * numberStyle/locale change behaves like Apple (custom formats survive). */
- (void)_replaceFormatterWithStyle:(CFNumberFormatterStyle)style
                            locale:(CFLocaleRef)locale {
    CFNumberFormatterRef replacement = CFNumberFormatterCreate(
        kCFAllocatorDefault, locale, style);
    if (replacement == NULL) return;
    if (_customFormat != nil) {
        CFNumberFormatterSetFormat(replacement,
            NNFORMATTER_CF(CFStringRef, _customFormat));
    }
    CFRelease(_formatter);
    _formatter = replacement;
}

- (NSLocale *)locale {
    CFLocaleRef locale = CFLocaleCreateCopy(kCFAllocatorDefault,
                                            CFNumberFormatterGetLocale(_formatter));
    if (locale == NULL) return [NSLocale currentLocale];
    return [[NSLocale alloc] _initWithBackingLocale:locale];
}

- (void)setLocale:(NSLocale *)locale {
    if (locale == nil) locale = [NSLocale currentLocale];
    CFLocaleRef cfLocale = NULL;
    if ([locale isKindOfClass:[NSLocale class]]) {
        cfLocale = [locale _backingLocale];
    } else {
        cfLocale = NNFORMATTER_CF(CFLocaleRef, locale);
    }
    [self _replaceFormatterWithStyle:CFNumberFormatterGetStyle(_formatter)
                              locale:cfLocale];
}

- (NSNumberFormatterStyle)numberStyle {
    return (NSNumberFormatterStyle)CFNumberFormatterGetStyle(_formatter);
}

- (void)setNumberStyle:(NSNumberFormatterStyle)style {
    [self _replaceFormatterWithStyle:(CFNumberFormatterStyle)style
                              locale:CFNumberFormatterGetLocale(_formatter)];
}

- (NSString *)format {
    CFStringRef format = CFNumberFormatterGetFormat(_formatter);
    if (format == NULL) return nil;
    return NNFORMATTER_TRANSFER(CFStringCreateCopy(kCFAllocatorDefault, format));
}

- (void)setFormat:(NSString *)format {
#if __has_feature(objc_arc)
    _customFormat = [format copy];
#else
    [_customFormat release];
    _customFormat = [format copy];
#endif
    CFNumberFormatterSetFormat(_formatter,
        format ? NNFORMATTER_CF(CFStringRef, format) : NULL);
}

+ (NSString *)localizedStringFromNumber:(NSNumber *)number
                             numberStyle:(NSNumberFormatterStyle)numberStyle {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = numberStyle;
    return [formatter stringFromNumber:number];
}

- (NSString *)stringFromNumber:(NSNumber *)number {
    if (number == nil) return nil;
    return NNFORMATTER_TRANSFER(CFNumberFormatterCreateStringWithNumber(
        kCFAllocatorDefault, _formatter, NNFORMATTER_CF(CFNumberRef, number)));
}

- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSNumber class]]) return [self stringFromNumber:obj];
    return nil;
}

- (NSNumber *)numberFromString:(NSString *)string {
    if (string == nil) return nil;
    CFRange range = CFRangeMake(0, (CFIndex)[string length]);
    CFNumberRef number = CFNumberFormatterCreateNumberFromString(
        kCFAllocatorDefault, _formatter, NNFORMATTER_CF(CFStringRef, string),
        &range, 0);
    if (number == NULL) return nil;
    /* Apple requires the whole string to be consumed. */
    if (range.location != 0 || range.length != (CFIndex)[string length]) {
        CFRelease(number);
        return nil;
    }
    return NNFORMATTER_TRANSFER(number);
}

- (BOOL)getObjectValue:(id *)obj
             forString:(NSString *)string
                 range:(NSRange *)rangep
                 error:(NSError **)error {
    if (obj == nil) return NO;
    *obj = nil;
    if (error != nil) *error = nil;
    CFRange range = CFRangeMake(rangep ? rangep->location : 0,
                                rangep ? rangep->length : (CFIndex)[string length]);
    double value = 0.0;
    Boolean ok = CFNumberFormatterGetValueFromString(
        _formatter, NNFORMATTER_CF(CFStringRef, string), &range,
        kCFNumberDoubleType, &value);
    if (!ok) {
        if (error != nil) {
            NSString *desc = [NSString stringWithFormat:
                @"The value \u201C%@\u201D is invalid.", string];
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                          code:NSFormattingError
                                      userInfo:@{
                NSLocalizedDescriptionKey : desc,
                @"NSInvalidValue" : (string ?: (id)[NSNull null])
            }];
        }
        return NO;
    }
    if (rangep != NULL) {
        rangep->location = (NSUInteger)range.location;
        rangep->length = (NSUInteger)range.length;
    }
    *obj = NNFORMATTER_TRANSFER(CFNumberCreate(kCFAllocatorDefault,
                                               kCFNumberDoubleType, &value));
    return YES;
}

/* ---- property bridges ---- */

static CFTypeRef _NNCopyProperty(NSNumberFormatter *formatter, CFStringRef key) {
    return CFNumberFormatterCopyProperty(formatter->_formatter, key);
}

static BOOL _NNBoolForProperty(NSNumberFormatter *formatter, CFStringRef key) {
    CFTypeRef value = _NNCopyProperty(formatter, key);
    BOOL result = (value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID() &&
                   CFBooleanGetValue((CFBooleanRef)value));
    if (value != NULL) CFRelease(value);
    return result;
}

static void _NNSetBoolProperty(NSNumberFormatter *formatter, CFStringRef key,
                               BOOL value) {
    CFNumberFormatterSetProperty(formatter->_formatter, key,
                                 value ? kCFBooleanTrue : kCFBooleanFalse);
}

static long long _NNSignedForProperty(NSNumberFormatter *formatter, CFStringRef key) {
    CFTypeRef value = _NNCopyProperty(formatter, key);
    long long result = 0;
    if (value != NULL && CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &result);
    }
    if (value != NULL) CFRelease(value);
    return result;
}

static void _NNSetSignedProperty(NSNumberFormatter *formatter, CFStringRef key,
                                 long long value) {
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberLongLongType, &value);
    if (number != NULL) {
        CFNumberFormatterSetProperty(formatter->_formatter, key, number);
        CFRelease(number);
    }
}

static id _NNStringForProperty(NSNumberFormatter *formatter, CFStringRef key) {
    CFTypeRef value = _NNCopyProperty(formatter, key);
    if (value == NULL) return nil;
    CFStringRef copy = CFStringCreateCopy(kCFAllocatorDefault,
                                          (CFStringRef)value);
    return NNFORMATTER_TRANSFER(copy);
}

static void _NNSetStringProperty(NSNumberFormatter *formatter, CFStringRef key,
                                 NSString *value) {
    CFNumberFormatterSetProperty(formatter->_formatter, key,
                                 value ? NNFORMATTER_CF(CFStringRef, value) : NULL);
}

- (BOOL)lenient { return _NNBoolForProperty(self, kCFNumberFormatterIsLenient); }
- (void)setLenient:(BOOL)value { _NNSetBoolProperty(self, kCFNumberFormatterIsLenient, value); }
- (NSString *)decimalSeparator { return _NNStringForProperty(self, kCFNumberFormatterDecimalSeparator); }
- (void)setDecimalSeparator:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterDecimalSeparator, value); }
- (NSString *)groupingSeparator { return _NNStringForProperty(self, kCFNumberFormatterGroupingSeparator); }
- (void)setGroupingSeparator:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterGroupingSeparator, value); }
- (NSString *)currencyDecimalSeparator { return _NNStringForProperty(self, kCFNumberFormatterCurrencyDecimalSeparator); }
- (void)setCurrencyDecimalSeparator:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterCurrencyDecimalSeparator, value); }
- (BOOL)usesGroupingSeparator { return _NNBoolForProperty(self, kCFNumberFormatterUseGroupingSeparator); }
- (void)setUsesGroupingSeparator:(BOOL)value { _NNSetBoolProperty(self, kCFNumberFormatterUseGroupingSeparator, value); }
- (BOOL)alwaysShowsDecimalSeparator { return _NNBoolForProperty(self, kCFNumberFormatterAlwaysShowDecimalSeparator); }
- (void)setAlwaysShowsDecimalSeparator:(BOOL)value { _NNSetBoolProperty(self, kCFNumberFormatterAlwaysShowDecimalSeparator, value); }
- (NSUInteger)groupingSize { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterGroupingSize); }
- (void)setGroupingSize:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterGroupingSize, (long long)value); }
- (NSUInteger)secondaryGroupingSize { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterSecondaryGroupingSize); }
- (void)setSecondaryGroupingSize:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterSecondaryGroupingSize, (long long)value); }
- (NSUInteger)minimumIntegerDigits { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterMinIntegerDigits); }
- (void)setMinimumIntegerDigits:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterMinIntegerDigits, (long long)value); }
- (NSUInteger)maximumIntegerDigits { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterMaxIntegerDigits); }
- (void)setMaximumIntegerDigits:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterMaxIntegerDigits, (long long)value); }
- (NSUInteger)minimumFractionDigits { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterMinFractionDigits); }
- (void)setMinimumFractionDigits:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterMinFractionDigits, (long long)value); }
- (NSUInteger)maximumFractionDigits { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterMaxFractionDigits); }
- (void)setMaximumFractionDigits:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterMaxFractionDigits, (long long)value); }
- (BOOL)usesSignificantDigits { return _NNBoolForProperty(self, kCFNumberFormatterUseSignificantDigits); }
- (void)setUsesSignificantDigits:(BOOL)value { _NNSetBoolProperty(self, kCFNumberFormatterUseSignificantDigits, value); }
- (NSUInteger)minimumSignificantDigits { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterMinSignificantDigits); }
- (void)setMinimumSignificantDigits:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterMinSignificantDigits, (long long)value); }
- (NSUInteger)maximumSignificantDigits { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterMaxSignificantDigits); }
- (void)setMaximumSignificantDigits:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterMaxSignificantDigits, (long long)value); }
- (NSNumberFormatterRoundingMode)roundingMode { return (NSNumberFormatterRoundingMode)_NNSignedForProperty(self, kCFNumberFormatterRoundingMode); }
- (void)setRoundingMode:(NSNumberFormatterRoundingMode)value { _NNSetSignedProperty(self, kCFNumberFormatterRoundingMode, (long long)value); }
- (NSNumber *)roundingIncrement {
    CFTypeRef value = _NNCopyProperty(self, kCFNumberFormatterRoundingIncrement);
    if (value == NULL) return nil;
    double result = 0.0;
    CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    CFRelease(value);
    return NNFORMATTER_TRANSFER(CFNumberCreate(kCFAllocatorDefault,
                                               kCFNumberDoubleType, &result));
}
- (void)setRoundingIncrement:(NSNumber *)value {
    if (value == nil) {
        CFNumberFormatterSetProperty(_formatter, kCFNumberFormatterRoundingIncrement, NULL);
        return;
    }
    double result = [value doubleValue];
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberDoubleType, &result);
    if (number != NULL) {
        CFNumberFormatterSetProperty(_formatter, kCFNumberFormatterRoundingIncrement, number);
        CFRelease(number);
    }
}
- (NSString *)plusSign { return _NNStringForProperty(self, kCFNumberFormatterPlusSign); }
- (void)setPlusSign:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterPlusSign, value); }
- (NSString *)minusSign { return _NNStringForProperty(self, kCFNumberFormatterMinusSign); }
- (void)setMinusSign:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterMinusSign, value); }
- (NSString *)notANumberSymbol { return _NNStringForProperty(self, kCFNumberFormatterNaNSymbol); }
- (void)setNotANumberSymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterNaNSymbol, value); }
- (NSString *)zeroSymbol { return _NNStringForProperty(self, kCFNumberFormatterZeroSymbol); }
- (void)setZeroSymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterZeroSymbol, value); }
- (NSString *)infinitySymbol { return _NNStringForProperty(self, kCFNumberFormatterInfinitySymbol); }
- (void)setInfinitySymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterInfinitySymbol, value); }
- (NSString *)positivePrefix { return _NNStringForProperty(self, kCFNumberFormatterPositivePrefix); }
- (void)setPositivePrefix:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterPositivePrefix, value); }
- (NSString *)positiveSuffix { return _NNStringForProperty(self, kCFNumberFormatterPositiveSuffix); }
- (void)setPositiveSuffix:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterPositiveSuffix, value); }
- (NSString *)negativePrefix { return _NNStringForProperty(self, kCFNumberFormatterNegativePrefix); }
- (void)setNegativePrefix:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterNegativePrefix, value); }
- (NSString *)negativeSuffix { return _NNStringForProperty(self, kCFNumberFormatterNegativeSuffix); }
- (void)setNegativeSuffix:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterNegativeSuffix, value); }
- (NSString *)percentSymbol { return _NNStringForProperty(self, kCFNumberFormatterPercentSymbol); }
- (void)setPercentSymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterPercentSymbol, value); }
- (NSString *)perMillSymbol { return _NNStringForProperty(self, kCFNumberFormatterPerMillSymbol); }
- (void)setPerMillSymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterPerMillSymbol, value); }
- (NSString *)currencySymbol { return _NNStringForProperty(self, kCFNumberFormatterCurrencySymbol); }
- (void)setCurrencySymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterCurrencySymbol, value); }
- (NSString *)currencyCode { return _NNStringForProperty(self, kCFNumberFormatterCurrencyCode); }
- (void)setCurrencyCode:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterCurrencyCode, value); }
- (NSString *)internationalCurrencySymbol { return _NNStringForProperty(self, kCFNumberFormatterInternationalCurrencySymbol); }
- (void)setInternationalCurrencySymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterInternationalCurrencySymbol, value); }
- (NSString *)exponentSymbol { return _NNStringForProperty(self, kCFNumberFormatterExponentSymbol); }
- (void)setExponentSymbol:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterExponentSymbol, value); }
- (NSNumber *)multiplier {
    CFTypeRef value = _NNCopyProperty(self, kCFNumberFormatterMultiplier);
    if (value == NULL) return nil;
    double result = 0.0;
    CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    CFRelease(value);
    return NNFORMATTER_TRANSFER(CFNumberCreate(kCFAllocatorDefault,
                                               kCFNumberDoubleType, &result));
}
- (void)setMultiplier:(NSNumber *)value {
    if (value == nil) {
        CFNumberFormatterSetProperty(_formatter, kCFNumberFormatterMultiplier, NULL);
        return;
    }
    double result = [value doubleValue];
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberDoubleType, &result);
    if (number != NULL) {
        CFNumberFormatterSetProperty(_formatter, kCFNumberFormatterMultiplier, number);
        CFRelease(number);
    }
}
- (NSUInteger)formatWidth { return (NSUInteger)_NNSignedForProperty(self, kCFNumberFormatterFormatWidth); }
- (void)setFormatWidth:(NSUInteger)value { _NNSetSignedProperty(self, kCFNumberFormatterFormatWidth, (long long)value); }
- (NSNumberFormatterPadPosition)paddingPosition { return (NSNumberFormatterPadPosition)_NNSignedForProperty(self, kCFNumberFormatterPaddingPosition); }
- (void)setPaddingPosition:(NSNumberFormatterPadPosition)value { _NNSetSignedProperty(self, kCFNumberFormatterPaddingPosition, (long long)value); }
- (NSString *)paddingCharacter { return _NNStringForProperty(self, kCFNumberFormatterPaddingCharacter); }
- (void)setPaddingCharacter:(NSString *)value { _NNSetStringProperty(self, kCFNumberFormatterPaddingCharacter, value); }

@end