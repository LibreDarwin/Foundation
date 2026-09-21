/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSCalendar.h>
#include <CoreFoundation/CFCalendar.h>

#if __has_feature(objc_arc)
#define NSCALENDAR_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSCALENDAR_BORROWED(value) ((__bridge id)(value))
#define NSCALENDAR_CF(type, value) ((__bridge type)(value))
#else
#define NSCALENDAR_TRANSFER(value) ((id)CFAutorelease(value))
#define NSCALENDAR_BORROWED(value) ((id)(value))
#define NSCALENDAR_CF(type, value) ((type)(value))
#endif

NSCalendarIdentifier const NSCalendarIdentifierGregorian = @"gregorian";
NSCalendarIdentifier const NSCalendarIdentifierISO8601 = @"iso8601";
NSCalendarIdentifier const NSCalendarIdentifierBuddhist = @"buddhist";
NSCalendarIdentifier const NSCalendarIdentifierJapanese = @"japanese";

static CFCalendarUnit NSCalendarCFUnit(NSCalendarUnit unit) {
    return (CFCalendarUnit)unit;
}

/* Decompose and compose take their arguments differently, and the difference
 * matters: CFCalendarDecomposeAbsoluteTime and
 * CFCalendarGetComponentDifference fill in out-parameters passed by address,
 * while CFCalendarComposeAbsoluteTime and CFCalendarAddComponents read their
 * inputs by value. The component descriptor characters are, in order: era G,
 * year y, quarter Q, month M, week of month W, week of year w, year for week of
 * year Y, day d, weekday E, weekday ordinal F, hour H, minute m, second s. */
static const char NSCalendarAllComponentsDescriptor[] = "GyQMWwYdEFHms";

static int NSCalendarComponentOrDefault(NSInteger value, NSInteger fallback) {
    return (int)(value == NSDateComponentUndefined ? fallback : value);
}

@implementation NSCalendar

+ (instancetype)calendarWithIdentifier:(NSCalendarIdentifier)identifier {
    return NSCALENDAR_TRANSFER(CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, NSCALENDAR_CF(CFStringRef, identifier)));
}

- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)identifier {
    return NSCALENDAR_TRANSFER(CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, NSCALENDAR_CF(CFStringRef, identifier)));
}

- (NSCalendarIdentifier)calendarIdentifier {
    return NSCALENDAR_BORROWED(CFCalendarGetIdentifier(NSCALENDAR_CF(CFCalendarRef, self)));
}

- (NSUInteger)firstWeekday {
    return (NSUInteger)CFCalendarGetFirstWeekday(NSCALENDAR_CF(CFCalendarRef, self));
}

- (void)setFirstWeekday:(NSUInteger)firstWeekday {
    CFCalendarSetFirstWeekday(NSCALENDAR_CF(CFCalendarRef, self), (CFIndex)firstWeekday);
}

- (NSUInteger)minimumDaysInFirstWeek {
    return (NSUInteger)CFCalendarGetMinimumDaysInFirstWeek(NSCALENDAR_CF(CFCalendarRef, self));
}

- (void)setMinimumDaysInFirstWeek:(NSUInteger)minimumDaysInFirstWeek {
    CFCalendarSetMinimumDaysInFirstWeek(NSCALENDAR_CF(CFCalendarRef, self),
                                        (CFIndex)minimumDaysInFirstWeek);
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    int era = 0, year = 0, quarter = 0, month = 0, weekOfMonth = 0, weekOfYear = 0, yearForWeekOfYear = 0;
    int day = 0, weekday = 0, weekdayOrdinal = 0, hour = 0, minute = 0, second = 0;
    if (!CFCalendarDecomposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), absoluteTime,
                                         NSCalendarAllComponentsDescriptor,
                                         &era, &year, &quarter, &month, &weekOfMonth, &weekOfYear,
                                         &yearForWeekOfYear, &day, &weekday, &weekdayOrdinal,
                                         &hour, &minute, &second)) return components;
    if (unitFlags & NSCalendarUnitEra) components.era = era;
    if (unitFlags & NSCalendarUnitYear) components.year = year;
    if (unitFlags & NSCalendarUnitQuarter) components.quarter = quarter;
    if (unitFlags & NSCalendarUnitMonth) components.month = month;
    if (unitFlags & NSCalendarUnitWeekOfMonth) components.weekOfMonth = weekOfMonth;
    if (unitFlags & NSCalendarUnitWeekOfYear) components.weekOfYear = weekOfYear;
    if (unitFlags & NSCalendarUnitYearForWeekOfYear) components.yearForWeekOfYear = yearForWeekOfYear;
    if (unitFlags & NSCalendarUnitDay) components.day = day;
    if (unitFlags & NSCalendarUnitWeekday) components.weekday = weekday;
    if (unitFlags & NSCalendarUnitWeekdayOrdinal) components.weekdayOrdinal = weekdayOrdinal;
    if (unitFlags & NSCalendarUnitHour) components.hour = hour;
    if (unitFlags & NSCalendarUnitMinute) components.minute = minute;
    if (unitFlags & NSCalendarUnitSecond) components.second = second;
    return components;
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags
                        fromDate:(NSDate *)startingDate
                          toDate:(NSDate *)resultDate
                         options:(NSUInteger)options {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    CFAbsoluteTime startingTime = [startingDate timeIntervalSinceReferenceDate];
    CFAbsoluteTime resultTime = [resultDate timeIntervalSinceReferenceDate];
    int era = 0, year = 0, quarter = 0, month = 0, weekOfMonth = 0, weekOfYear = 0, yearForWeekOfYear = 0;
    int day = 0, weekday = 0, weekdayOrdinal = 0, hour = 0, minute = 0, second = 0;

    /* The difference for a unit depends on which other units travel with it:
     * asking for days alone yields the total day count, while asking for days
     * and months splits it into whole months plus a remainder. So the
     * descriptor has to carry exactly the requested units, in canonical order. */
    char descriptor[16];
    int *results[13];
    int count = 0;
#define NSCALENDAR_DIFFERENCE_UNIT(flag, character, variable)     \
    if (unitFlags & (flag)) {                                     \
        descriptor[count] = (character);                          \
        results[count] = &(variable);                             \
        count++;                                                  \
    }
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitEra, 'G', era)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitYear, 'y', year)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitQuarter, 'Q', quarter)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitMonth, 'M', month)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekOfMonth, 'W', weekOfMonth)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekOfYear, 'w', weekOfYear)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitYearForWeekOfYear, 'Y', yearForWeekOfYear)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitDay, 'd', day)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekday, 'E', weekday)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekdayOrdinal, 'F', weekdayOrdinal)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitHour, 'H', hour)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitMinute, 'm', minute)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitSecond, 's', second)
#undef NSCALENDAR_DIFFERENCE_UNIT
    descriptor[count] = '\0';

    CFCalendarRef calendar = NSCALENDAR_CF(CFCalendarRef, self);
    CFOptionFlags flags = (CFOptionFlags)options;
    Boolean ok = false;
    switch (count) {
        case 0:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor); break;
        case 1:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0]); break;
        case 2:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1]); break;
        case 3:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2]); break;
        case 4:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3]); break;
        case 5:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4]); break;
        case 6:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5]); break;
        case 7:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6]); break;
        case 8:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7]); break;
        case 9:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8]); break;
        case 10: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9]); break;
        case 11: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9], results[10]); break;
        case 12: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9], results[10], results[11]); break;
        default: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9], results[10], results[11], results[12]); break;
    }
    if (!ok) return components;
    if (unitFlags & NSCalendarUnitEra) components.era = era;
    if (unitFlags & NSCalendarUnitYear) components.year = year;
    if (unitFlags & NSCalendarUnitQuarter) components.quarter = quarter;
    if (unitFlags & NSCalendarUnitMonth) components.month = month;
    if (unitFlags & NSCalendarUnitWeekOfMonth) components.weekOfMonth = weekOfMonth;
    if (unitFlags & NSCalendarUnitWeekOfYear) components.weekOfYear = weekOfYear;
    if (unitFlags & NSCalendarUnitYearForWeekOfYear) components.yearForWeekOfYear = yearForWeekOfYear;
    if (unitFlags & NSCalendarUnitDay) components.day = day;
    if (unitFlags & NSCalendarUnitWeekday) components.weekday = weekday;
    if (unitFlags & NSCalendarUnitWeekdayOrdinal) components.weekdayOrdinal = weekdayOrdinal;
    if (unitFlags & NSCalendarUnitHour) components.hour = hour;
    if (unitFlags & NSCalendarUnitMinute) components.minute = minute;
    if (unitFlags & NSCalendarUnitSecond) components.second = second;
    return components;
}

- (NSDate *)dateFromComponents:(NSDateComponents *)components {
    int era = NSCalendarComponentOrDefault(components.era, 1);
    int year = NSCalendarComponentOrDefault(components.year, 1);
    int month = NSCalendarComponentOrDefault(components.month, 1);
    int day = NSCalendarComponentOrDefault(components.day, 1);
    int hour = NSCalendarComponentOrDefault(components.hour, 0);
    int minute = NSCalendarComponentOrDefault(components.minute, 0);
    int second = NSCalendarComponentOrDefault(components.second, 0);
    CFAbsoluteTime absoluteTime = 0;
    if (!CFCalendarComposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
                                        "GyMdHms", era, year, month, day,
                                        hour, minute, second)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSDate *)dateByAddingComponents:(NSDateComponents *)components
                            toDate:(NSDate *)date
                           options:(NSUInteger)options {
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    int era = NSCalendarComponentOrDefault(components.era, 0);
    int year = NSCalendarComponentOrDefault(components.year, 0);
    int quarter = NSCalendarComponentOrDefault(components.quarter, 0);
    int month = NSCalendarComponentOrDefault(components.month, 0);
    int weekOfMonth = NSCalendarComponentOrDefault(components.weekOfMonth, 0);
    int weekOfYear = NSCalendarComponentOrDefault(components.weekOfYear, 0);
    int yearForWeekOfYear = NSCalendarComponentOrDefault(components.yearForWeekOfYear, 0);
    int day = NSCalendarComponentOrDefault(components.day, 0);
    int weekday = NSCalendarComponentOrDefault(components.weekday, 0);
    int weekdayOrdinal = NSCalendarComponentOrDefault(components.weekdayOrdinal, 0);
    int hour = NSCalendarComponentOrDefault(components.hour, 0);
    int minute = NSCalendarComponentOrDefault(components.minute, 0);
    int second = NSCalendarComponentOrDefault(components.second, 0);
    if (!CFCalendarAddComponents(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
                                 (CFOptionFlags)options, NSCalendarAllComponentsDescriptor,
                                 era, year, quarter, month, weekOfMonth, weekOfYear,
                                 yearForWeekOfYear, day, weekday, weekdayOrdinal,
                                 hour, minute, second)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)value toDate:(NSDate *)date options:(NSUInteger)options {
    const char *descriptor = NULL;
    switch (unit) {
        case NSCalendarUnitEra: descriptor = "G"; break;
        case NSCalendarUnitYear: descriptor = "y"; break;
        case NSCalendarUnitQuarter: descriptor = "Q"; break;
        case NSCalendarUnitMonth: descriptor = "M"; break;
        case NSCalendarUnitWeekOfMonth: descriptor = "W"; break;
        case NSCalendarUnitWeekOfYear: descriptor = "w"; break;
        case NSCalendarUnitYearForWeekOfYear: descriptor = "Y"; break;
        case NSCalendarUnitDay: descriptor = "d"; break;
        case NSCalendarUnitWeekday: descriptor = "E"; break;
        case NSCalendarUnitWeekdayOrdinal: descriptor = "F"; break;
        case NSCalendarUnitHour: descriptor = "H"; break;
        case NSCalendarUnitMinute: descriptor = "m"; break;
        case NSCalendarUnitSecond: descriptor = "s"; break;
        default: return nil;
    }
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    if (!CFCalendarAddComponents(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
                                 (CFOptionFlags)options, descriptor, (int)value)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    CFRange range = CFCalendarGetRangeOfUnit(NSCALENDAR_CF(CFCalendarRef, self),
                                             (CFCalendarUnit)smaller, (CFCalendarUnit)larger,
                                             [date timeIntervalSinceReferenceDate]);
    /* CoreFoundation reports an unsupported pairing as kCFNotFound; NSRange
     * spells the same thing NSNotFound. */
    if (range.location == kCFNotFound || range.length == kCFNotFound) {
        return NSMakeRange(NSNotFound, NSNotFound);
    }
    return NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return NSCALENDAR_TRANSFER(CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, CFCalendarGetIdentifier(NSCALENDAR_CF(CFCalendarRef, self))));
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFCalendarBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFCalendarGetTypeID(), "NSCalendar");
}
#endif
