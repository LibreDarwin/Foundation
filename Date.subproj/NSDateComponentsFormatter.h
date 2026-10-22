/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSDateComponentsFormatter_h
#define NSDateComponentsFormatter_h

#import <Foundation/NSFormatter.h>
#import <Foundation/NSCalendar.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSDate.h>

typedef NS_ENUM(NSInteger, NSDateComponentsFormatterUnitsStyle) {
    NSDateComponentsFormatterUnitsStylePositional = 0,
    NSDateComponentsFormatterUnitsStyleAbbreviated,
    NSDateComponentsFormatterUnitsStyleShort,
    NSDateComponentsFormatterUnitsStyleFull,
    NSDateComponentsFormatterUnitsStyleSpellOut,
    NSDateComponentsFormatterUnitsStyleBrief
};

typedef NS_OPTIONS(NSUInteger, NSDateComponentsFormatterZeroFormattingBehavior) {
    NSDateComponentsFormatterZeroFormattingBehaviorNone = (0),
    NSDateComponentsFormatterZeroFormattingBehaviorDefault = (1 << 0),
    NSDateComponentsFormatterZeroFormattingBehaviorDropLeading = (1 << 1),
    NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle = (1 << 2),
    NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing = (1 << 3),
    NSDateComponentsFormatterZeroFormattingBehaviorDropAll =
        (NSDateComponentsFormatterZeroFormattingBehaviorDropLeading |
         NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle |
         NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing),
    NSDateComponentsFormatterZeroFormattingBehaviorPad = (1 << 16)
};

/* Formats quantities of time expressed as NSDateComponents, a pair of dates,
 * or a number of seconds.  The formatter is not a parser. */
@interface NSDateComponentsFormatter : NSFormatter

/* 'obj' must be an instance of NSDateComponents. */
- (nullable NSString *)stringForObjectValue:(nullable id)obj;

/* Counts the units starting from referenceDate. */
- (nullable NSString *)stringFromDateComponents:(NSDateComponents *)components;

/* Counts the units starting from startDate rather than referenceDate. */
- (nullable NSString *)stringFromDate:(NSDate *)startDate toDate:(NSDate *)endDate;

/* Counts the units from referenceDate to the given interval. */
- (nullable NSString *)stringFromTimeInterval:(NSTimeInterval)ti;

+ (nullable NSString *)localizedStringFromDateComponents:(NSDateComponents *)components
                                               unitsStyle:(NSDateComponentsFormatterUnitsStyle)unitsStyle;

/* Default is NSDateComponentsFormatterUnitsStylePositional. */
@property NSDateComponentsFormatterUnitsStyle unitsStyle;

/* Bitmask of units to include; 0 means use the units present in the
 * components object, or every unit for an interval.  Only the seven quantity
 * units (year, month, week of month, day, hour, minute, second) are legal. */
@property NSCalendarUnit allowedUnits;

/* Default is NSDateComponentsFormatterZeroFormattingBehaviorDefault. */
@property NSDateComponentsFormatterZeroFormattingBehavior zeroFormattingBehavior;

/* Defaults to the autoupdating current calendar.  Setting nil selects the
 * Gregorian calendar with the en_US_POSIX locale. */
@property (nullable, copy) NSCalendar *calendar;

/* Defaults to [NSDate dateWithTimeIntervalSinceReferenceDate:0]. */
@property (nullable, copy) NSDate *referenceDate;

@property BOOL allowsFractionalUnits;

/* 0 means unlimited. */
@property NSInteger maximumUnitCount;

/* Express the largest unit as a larger quantity of the next unit when it is
 * just above the threshold, e.g. "63s" instead of "1m 3s". */
@property BOOL collapsesLargestUnit;

@property BOOL includesApproximationPhrase;

@property BOOL includesTimeRemainingPhrase;

/* Not yet supported. */
@property NSFormattingContext formattingContext;

/* This class only implements formatting, so this always returns NO. */
- (BOOL)getObjectValue:(out id _Nullable * _Nullable)obj
             forString:(NSString *)string
      errorDescription:(out NSString * _Nullable * _Nullable)error;

@end

#endif /* NSDateComponentsFormatter_h */
