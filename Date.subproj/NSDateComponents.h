/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSDateComponents_h
#define NSDateComponents_h

#import <Foundation/NSObject.h>
#import <Foundation/NSCalendarUnit.h>

/* When a date components object is created every field begins Undefined; a
 * value only becomes meaningful once it has been set. */
enum {
    NSDateComponentUndefined = NSIntegerMax,
    NSUndefinedDateComponent = NSDateComponentUndefined
};

@class NSDate;
@class NSCalendar;

@interface NSDateComponents : NSObject <NSCopying, NSSecureCoding>

@property (nullable, copy) NSCalendar *calendar;

@property NSInteger era;
@property NSInteger year;
@property NSInteger month;
@property NSInteger day;
@property NSInteger hour;
@property NSInteger minute;
@property NSInteger second;
@property NSInteger nanosecond;
@property NSInteger weekday;
@property NSInteger weekdayOrdinal;
@property NSInteger quarter;
@property NSInteger weekOfMonth;
@property NSInteger weekOfYear;
@property NSInteger yearForWeekOfYear;
@property NSInteger dayOfYear;
@property (getter=isLeapMonth) BOOL leapMonth;
@property (getter=isRepeatedDay) BOOL repeatedDay;

/* The date produced by interpreting the set fields against `calendar`, or nil
 * when no calendar has been set. */
@property (nullable, readonly, copy) NSDate *date;

/* Deprecated spelling of the week of the year; an independent field rather
 * than an alias for weekOfMonth or weekOfYear. */
- (NSInteger)week;
- (void)setWeek:(NSInteger)v;

/* The calendar, time zone, and leap-month fields cannot be reached through
 * these. An unsupported unit leaves the receiver untouched and reads back as
 * Undefined. */
- (void)setValue:(NSInteger)value forComponent:(NSCalendarUnit)unit;
- (NSInteger)valueForComponent:(NSCalendarUnit)unit;

/* Whether the combination of set fields names a date that exists in the
 * calendar. The calendar property must be set for -isValidDate; returns NO
 * otherwise. */
@property (getter=isValidDate, readonly) BOOL validDate;
- (BOOL)isValidDateInCalendar:(NSCalendar *)calendar;

@end

#endif /* NSDateComponents_h */
