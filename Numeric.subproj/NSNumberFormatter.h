/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSNumberFormatter_h
#define NSNumberFormatter_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSError.h>

@class NSString, NSNumber, NSLocale, NSError, NSDictionary;

typedef NS_ENUM(NSUInteger, NSNumberFormatterStyle) {
    NSNumberFormatterNoStyle = 0,
    NSNumberFormatterDecimalStyle = 1,
    NSNumberFormatterCurrencyStyle = 2,
    NSNumberFormatterPercentStyle = 3,
    NSNumberFormatterScientificStyle = 4,
    NSNumberFormatterSpellOutStyle = 5
};

typedef NS_ENUM(NSUInteger, NSNumberFormatterRoundingMode) {
    NSNumberFormatterRoundCeiling = 0,
    NSNumberFormatterRoundFloor = 1,
    NSNumberFormatterRoundDown = 2,
    NSNumberFormatterRoundUp = 3,
    NSNumberFormatterRoundHalfEven = 4,
    NSNumberFormatterRoundHalfDown = 5,
    NSNumberFormatterRoundHalfUp = 6
};

typedef NS_ENUM(NSUInteger, NSNumberFormatterPadPosition) {
    NSNumberFormatterPadBeforePrefix = 0,
    NSNumberFormatterPadAfterPrefix = 1,
    NSNumberFormatterPadBeforeSuffix = 2,
    NSNumberFormatterPadAfterSuffix = 3
};

@interface NSNumberFormatter : NSObject

+ (NSString *)localizedStringFromNumber:(NSNumber *)number
                             numberStyle:(NSNumberFormatterStyle)numberStyle;

@property (nullable, copy) NSLocale *locale;
@property NSNumberFormatterStyle numberStyle;
@property (nullable, copy) NSString *format;

- (nullable NSString *)stringFromNumber:(NSNumber *)number;
- (nullable NSNumber *)numberFromString:(NSString *)string;
- (NSString *)stringForObjectValue:(id)obj;
- (BOOL)getObjectValue:(id *)obj
             forString:(NSString *)string
                 range:(NSRange *)rangep
                 error:(NSError **)error;

@property BOOL lenient;
@property (nullable, copy) NSString *decimalSeparator;
@property (nullable, copy) NSString *groupingSeparator;
@property (nullable, copy) NSString *currencyDecimalSeparator;
@property BOOL usesGroupingSeparator;
@property BOOL alwaysShowsDecimalSeparator;
@property NSUInteger groupingSize;
@property NSUInteger secondaryGroupingSize;
@property NSUInteger minimumIntegerDigits;
@property NSUInteger maximumIntegerDigits;
@property NSUInteger minimumFractionDigits;
@property NSUInteger maximumFractionDigits;
@property BOOL usesSignificantDigits;
@property NSUInteger minimumSignificantDigits;
@property NSUInteger maximumSignificantDigits;
@property NSNumberFormatterRoundingMode roundingMode;
@property (nullable, copy) NSNumber *roundingIncrement;
@property (nullable, copy) NSString *plusSign;
@property (nullable, copy) NSString *minusSign;
@property (nullable, copy) NSString *notANumberSymbol;
@property (nullable, copy) NSString *zeroSymbol;
@property (nullable, copy) NSString *infinitySymbol;
@property (nullable, copy) NSString *positivePrefix;
@property (nullable, copy) NSString *positiveSuffix;
@property (nullable, copy) NSString *negativePrefix;
@property (nullable, copy) NSString *negativeSuffix;
@property (nullable, copy) NSString *percentSymbol;
@property (nullable, copy) NSString *perMillSymbol;
@property (nullable, copy) NSString *currencySymbol;
@property (nullable, copy) NSString *currencyCode;
@property (nullable, copy) NSString *internationalCurrencySymbol;
@property (nullable, copy) NSString *exponentSymbol;
@property (nullable, copy) NSNumber *multiplier;
@property NSUInteger formatWidth;
@property NSNumberFormatterPadPosition paddingPosition;
@property (nullable, copy) NSString *paddingCharacter;

@end

#endif /* NSNumberFormatter_h */