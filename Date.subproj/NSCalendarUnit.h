/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSCalendarUnit_h
#define NSCalendarUnit_h

#import <Foundation/NSObject.h>

typedef NS_OPTIONS(NSUInteger, NSCalendarUnit) {
    NSCalendarUnitEra = (1UL << 1),
    NSCalendarUnitYear = (1UL << 2),
    NSCalendarUnitMonth = (1UL << 3),
    NSCalendarUnitDay = (1UL << 4),
    NSCalendarUnitHour = (1UL << 5),
    NSCalendarUnitMinute = (1UL << 6),
    NSCalendarUnitSecond = (1UL << 7),
    NSCalendarUnitWeekday = (1UL << 9),
    NSCalendarUnitWeekdayOrdinal = (1UL << 10),
    NSCalendarUnitQuarter = (1UL << 11),
    NSCalendarUnitWeekOfMonth = (1UL << 12),
    NSCalendarUnitWeekOfYear = (1UL << 13),
    NSCalendarUnitYearForWeekOfYear = (1UL << 14),
    NSCalendarUnitNanosecond = (1UL << 15),
    NSCalendarUnitDayOfYear = (1UL << 16),
    NSCalendarUnitCalendar = (1UL << 20),
    NSCalendarUnitTimeZone = (1UL << 21),
    NSCalendarUnitIsLeapMonth = (1UL << 30),
    NSCalendarUnitIsRepeatedDay = (1UL << 31),

    NSEraCalendarUnit = NSCalendarUnitEra,
    NSYearCalendarUnit = NSCalendarUnitYear,
    NSMonthCalendarUnit = NSCalendarUnitMonth,
    NSDayCalendarUnit = NSCalendarUnitDay,
    NSHourCalendarUnit = NSCalendarUnitHour,
    NSMinuteCalendarUnit = NSCalendarUnitMinute,
    NSSecondCalendarUnit = NSCalendarUnitSecond,
    NSWeekCalendarUnit = (1UL << 8),
    NSWeekdayCalendarUnit = NSCalendarUnitWeekday,
    NSWeekdayOrdinalCalendarUnit = NSCalendarUnitWeekdayOrdinal,
    NSQuarterCalendarUnit = NSCalendarUnitQuarter,
    NSWeekOfMonthCalendarUnit = NSCalendarUnitWeekOfMonth,
    NSWeekOfYearCalendarUnit = NSCalendarUnitWeekOfYear,
    NSYearForWeekOfYearCalendarUnit = NSCalendarUnitYearForWeekOfYear,
    NSCalendarCalendarUnit = NSCalendarUnitCalendar,
    NSTimeZoneCalendarUnit = NSCalendarUnitTimeZone
};

typedef NS_OPTIONS(NSUInteger, NSCalendarOptions) {
    NSCalendarWrapComponents = (1UL << 0),

    NSCalendarMatchStrictly = (1UL << 1),
    NSCalendarSearchBackwards = (1UL << 2),

    NSCalendarMatchPreviousTimePreservingSmallerUnits = (1UL << 8),
    NSCalendarMatchNextTimePreservingSmallerUnits = (1UL << 9),
    NSCalendarMatchNextTime = (1UL << 10),

    NSCalendarMatchFirst = (1UL << 12),
    NSCalendarMatchLast = (1UL << 13)
};

enum {
    NSWrapCalendarComponents = NSCalendarWrapComponents
};

#endif /* NSCalendarUnit_h */
