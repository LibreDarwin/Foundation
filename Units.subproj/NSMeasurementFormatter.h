/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef __NSMEASUREMENTFORMATTER_H
#define __NSMEASUREMENTFORMATTER_H 1

#import <Foundation/NSObject.h>
#import <Foundation/NSFormatter.h>
#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSMeasurement.h>
#import <Foundation/NSLocale.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, NSMeasurementFormatterUnitOptions) {
    /* Use the unit supplied with the measurement even if it is not the
     * preferred unit of the locale. */
    NSMeasurementFormatterUnitOptionsProvidedUnit = (1UL << 0),
    /* Scale the value within its unit system (e.g. "12 kilometers" instead of
     * "12000 meters"). */
    NSMeasurementFormatterUnitOptionsNaturalScale = (1UL << 1),
    /* Display temperature without its unit (e.g. "90\u00b0"). */
    NSMeasurementFormatterUnitOptionsTemperatureWithoutUnit = (1UL << 2)
};

@interface NSMeasurementFormatter : NSFormatter <NSSecureCoding> {
@private
    void *_formatter;
}

/* How the formatter treats the measurement's own unit; defaults to localizing
 * according to the locale. */
@property NSMeasurementFormatterUnitOptions unitOptions;

/* The localized width of the unit; defaults to NSFormattingUnitStyleMedium. */
@property NSFormattingUnitStyle unitStyle;

/* The locale used to localize units; defaults to the user's current locale. */
@property (null_resettable, copy) NSLocale *locale;

/* The number formatter used for the value; defaults to a decimal-style one. */
@property (null_resettable, copy) NSNumberFormatter *numberFormatter;

- (NSString *)stringFromMeasurement:(NSMeasurement *)measurement;

/* The localized display name of a unit without a value.  Returns the unit's
 * symbol if it cannot be localized. */
- (NSString *)stringFromUnit:(NSUnit *)unit;

@end

NS_ASSUME_NONNULL_END

#endif
